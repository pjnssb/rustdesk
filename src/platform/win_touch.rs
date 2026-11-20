use base::message_proto::{TouchContacts, TouchPhase::*};
use hbb_common::log;
use std::collections::HashMap;

pub const MAX_TOUCH_CONTACTS: usize = 10;

pub const PT_TOUCH: u32 = 0x0000_0002;
pub const TOUCH_FEEDBACK_DEFAULT: u32 = 0x1;
pub const TOUCH_FLAG_NONE: u32 = 0x0;
pub const TOUCH_MASK_CONTACTAREA: u32 = 0x0000_0001;
pub const TOUCH_MASK_ORIENTATION: u32 = 0x0000_0002;
pub const TOUCH_MASK_PRESSURE: u32 = 0x0000_0004;

pub const POINTER_FLAG_INRANGE: u32 = 0x0000_0002;
pub const POINTER_FLAG_INCONTACT: u32 = 0x0000_0004;
pub const POINTER_FLAG_CANCELED: u32 = 0x0000_8000;
pub const POINTER_FLAG_DOWN: u32 = 0x0001_0000;
pub const POINTER_FLAG_UPDATE: u32 = 0x0002_0000;
pub const POINTER_FLAG_UP: u32 = 0x0004_0000;

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct WinPoint {
    pub x: i32,
    pub y: i32,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct WinRect {
    pub left: i32,
    pub top: i32,
    pub right: i32,
    pub bottom: i32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct WinPointerInfo {
    pub pointer_type: u32,
    pub pointer_id: u32,
    pub frame_id: u32,
    pub pointer_flags: u32,
    pub source_device: usize,
    pub hwnd_target: usize,
    pub pt_pixel_location: WinPoint,
    pub pt_himetric_location: WinPoint,
    pub pt_pixel_location_raw: WinPoint,
    pub pt_himetric_location_raw: WinPoint,
    pub dw_time: u32,
    pub history_count: u32,
    pub input_data: i32,
    pub dw_key_states: u32,
    pub performance_count: u64,
    pub button_change_type: i32,
}

impl Default for WinPointerInfo {
    fn default() -> Self {
        unsafe { std::mem::zeroed() }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct WinPointerTouchInfo {
    pub pointer_info: WinPointerInfo,
    pub touch_flags: u32,
    pub touch_mask: u32,
    pub rc_contact: WinRect,
    pub rc_contact_raw: WinRect,
    pub orientation: u32,
    pub pressure: u32,
}

#[derive(Clone, Copy, Debug)]
struct ActiveContact {
    slot_id: u32,
    x: i32,
    y: i32,
    radius_x: i32,
    radius_y: i32,
    pressure: u32,
}

#[derive(Default)]
pub struct TouchTracker {
    active: HashMap<u32, ActiveContact>,
    used_slots: [bool; MAX_TOUCH_CONTACTS],
    frame_id: u32,
}

impl TouchTracker {
    fn alloc_slot(&mut self) -> Option<u32> {
        for (idx, used) in self.used_slots.iter_mut().enumerate() {
            if !*used {
                *used = true;
                return Some(idx as u32);
            }
        }
        None
    }

    fn free_slot(&mut self, slot_id: u32) {
        if let Some(used) = self.used_slots.get_mut(slot_id as usize) {
            *used = false;
        }
    }

    pub fn build_frame(&mut self, contacts: &TouchContacts) -> Vec<WinPointerTouchInfo> {
        self.frame_id = self.frame_id.wrapping_add(1);
        let mut frame_flags: HashMap<u32, (ActiveContact, u32, bool)> = HashMap::new();

        for (&remote_id, &contact) in &self.active {
            frame_flags.insert(
                remote_id,
                (
                    contact,
                    POINTER_FLAG_UPDATE | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT,
                    false,
                ),
            );
        }

        for c in &contacts.contacts {
            let phase = c.phase.enum_value_or(TouchMove);
            let rx = ((c.width.max(8) / 2) as i32).clamp(2, 64);
            let ry = ((c.height.max(8) / 2) as i32).clamp(2, 64);
            let pressure = if c.pressure == 0 {
                512
            } else {
                c.pressure.min(1024)
            };

            match phase {
                TouchDown => {
                    let slot_id = if let Some(existing) = self.active.get(&c.id) {
                        existing.slot_id
                    } else if let Some(slot) = self.alloc_slot() {
                        slot
                    } else {
                        continue;
                    };
                    let info = ActiveContact {
                        slot_id,
                        x: c.x,
                        y: c.y,
                        radius_x: rx,
                        radius_y: ry,
                        pressure,
                    };
                    let flag = if self.active.contains_key(&c.id) {
                        POINTER_FLAG_UPDATE | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT
                    } else {
                        POINTER_FLAG_DOWN | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT
                    };
                    self.active.insert(c.id, info);
                    frame_flags.insert(c.id, (info, flag, false));
                }
                TouchMove => {
                    if let Some(existing) = self.active.get_mut(&c.id) {
                        existing.x = c.x;
                        existing.y = c.y;
                        existing.radius_x = rx;
                        existing.radius_y = ry;
                        existing.pressure = pressure;
                        frame_flags.insert(
                            c.id,
                            (
                                *existing,
                                POINTER_FLAG_UPDATE | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT,
                                false,
                            ),
                        );
                    }
                }
                TouchUp | TouchCancel => {
                    if let Some(mut existing) = self.active.remove(&c.id) {
                        existing.x = c.x;
                        existing.y = c.y;
                        existing.radius_x = rx;
                        existing.radius_y = ry;
                        existing.pressure = pressure;
                        let flag = if phase == TouchCancel {
                            POINTER_FLAG_UP | POINTER_FLAG_CANCELED
                        } else {
                            POINTER_FLAG_UP
                        };
                        frame_flags.insert(c.id, (existing, flag, true));
                    }
                }
            }
        }

        let mut out = Vec::with_capacity(frame_flags.len());
        for (_, (contact, flags, release)) in frame_flags {
            if release {
                self.free_slot(contact.slot_id);
            }
            out.push(make_touch_info(contact, flags, self.frame_id));
        }
        out
    }

    pub fn clear_frame(&mut self) -> Vec<WinPointerTouchInfo> {
        if self.active.is_empty() {
            return Vec::new();
        }
        self.frame_id = self.frame_id.wrapping_add(1);
        let mut out = Vec::with_capacity(self.active.len());
        let drained: Vec<ActiveContact> = self.active.drain().map(|(_, c)| c).collect();
        for contact in drained {
            self.free_slot(contact.slot_id);
            out.push(make_touch_info(
                contact,
                POINTER_FLAG_UP | POINTER_FLAG_CANCELED,
                self.frame_id,
            ));
        }
        out
    }
}

fn make_touch_info(contact: ActiveContact, flags: u32, frame_id: u32) -> WinPointerTouchInfo {
    let rc = WinRect {
        left: contact.x - contact.radius_x,
        top: contact.y - contact.radius_y,
        right: contact.x + contact.radius_x,
        bottom: contact.y + contact.radius_y,
    };
    WinPointerTouchInfo {
        pointer_info: WinPointerInfo {
            pointer_type: PT_TOUCH,
            pointer_id: contact.slot_id,
            frame_id,
            pointer_flags: flags,
            pt_pixel_location: WinPoint {
                x: contact.x,
                y: contact.y,
            },
            pt_pixel_location_raw: WinPoint {
                x: contact.x,
                y: contact.y,
            },
            ..Default::default()
        },
        touch_flags: TOUCH_FLAG_NONE,
        touch_mask: TOUCH_MASK_CONTACTAREA | TOUCH_MASK_ORIENTATION | TOUCH_MASK_PRESSURE,
        rc_contact: rc,
        rc_contact_raw: rc,
        orientation: 0,
        pressure: contact.pressure,
    }
}

#[cfg(target_os = "windows")]
mod win_runtime {
    use super::*;
    use hbb_common::lazy_static;
    use std::sync::{Mutex, OnceLock};
    use winapi::shared::minwindef::{BOOL, TRUE};
    use winapi::um::errhandlingapi::GetLastError;
    use winapi::um::libloaderapi::{GetModuleHandleA, GetProcAddress};

    type FnInitializeTouchInjection = unsafe extern "system" fn(u32, u32) -> BOOL;
    type FnInjectTouchInput = unsafe extern "system" fn(u32, *const WinPointerTouchInfo) -> BOOL;

    struct TouchApis {
        init: FnInitializeTouchInjection,
        inject: FnInjectTouchInput,
    }

    static APIS: OnceLock<Option<TouchApis>> = OnceLock::new();

    lazy_static::lazy_static! {
        static ref TRACKER: Mutex<TouchTracker> = Mutex::new(TouchTracker::default());
        static ref TOUCH_INITED: Mutex<bool> = Mutex::new(false);
    }

    fn get_apis() -> Option<&'static TouchApis> {
        APIS.get_or_init(|| unsafe {
            let user32 = GetModuleHandleA(b"user32.dll\0".as_ptr() as _);
            if user32.is_null() {
                return None;
            }
            let init_ptr = GetProcAddress(user32, b"InitializeTouchInjection\0".as_ptr() as _);
            let inject_ptr = GetProcAddress(user32, b"InjectTouchInput\0".as_ptr() as _);
            if init_ptr.is_null() || inject_ptr.is_null() {
                return None;
            }
            Some(TouchApis {
                init: std::mem::transmute(init_ptr),
                inject: std::mem::transmute(inject_ptr),
            })
        })
        .as_ref()
    }

    fn ensure_initialized(apis: &TouchApis) -> bool {
        let mut inited = TOUCH_INITED.lock().unwrap();
        if *inited {
            return true;
        }
        let ok = unsafe { (apis.init)(MAX_TOUCH_CONTACTS as u32, TOUCH_FEEDBACK_DEFAULT) == TRUE };
        if ok {
            *inited = true;
        } else {
            let err = unsafe { GetLastError() };
            hbb_common::throttled_log!(
                std::time::Duration::from_secs(5),
                warn,
                "InitializeTouchInjection failed: error={err}"
            );
        }
        ok
    }

    pub fn inject_touch_contacts(contacts: &TouchContacts) {
        let Some(apis) = get_apis() else {
            return;
        };
        if !ensure_initialized(apis) {
            return;
        }
        let mut frame = {
            let mut tracker = TRACKER.lock().unwrap();
            tracker.build_frame(contacts)
        };
        if frame.is_empty() {
            return;
        }
        let ok = unsafe { (apis.inject)(frame.len() as u32, frame.as_ptr()) == TRUE };
        if !ok {
            let err = unsafe { GetLastError() };
            // Re-initialize once if desktop/session changed invalidated injection state.
            *TOUCH_INITED.lock().unwrap() = false;
            if ensure_initialized(apis) {
                let retry = unsafe { (apis.inject)(frame.len() as u32, frame.as_ptr()) == TRUE };
                if retry {
                    return;
                }
            }
            hbb_common::throttled_log!(
                std::time::Duration::from_secs(5),
                warn,
                "InjectTouchInput failed ({} contacts): error={err}",
                frame.len()
            );
            frame.clear();
            let cancel_frame = TRACKER.lock().unwrap().clear_frame();
            if !cancel_frame.is_empty() {
                unsafe {
                    (apis.inject)(cancel_frame.len() as u32, cancel_frame.as_ptr());
                }
            }
        }
    }

    pub fn reset_touches() {
        let Some(apis) = get_apis() else {
            return;
        };
        let cancel_frame = TRACKER.lock().unwrap().clear_frame();
        if !cancel_frame.is_empty() && *TOUCH_INITED.lock().unwrap() {
            unsafe {
                (apis.inject)(cancel_frame.len() as u32, cancel_frame.as_ptr());
            }
        }
    }
}

#[cfg(target_os = "windows")]
pub use win_runtime::{inject_touch_contacts, reset_touches};

#[cfg(not(target_os = "windows"))]
pub fn inject_touch_contacts(_contacts: &TouchContacts) {
    let _ = log::trace!("win_touch::inject_touch_contacts ignored on non-Windows");
}

#[cfg(not(target_os = "windows"))]
pub fn reset_touches() {}

#[cfg(test)]
mod tests {
    use super::*;
    use base::message_proto::TouchContact;

    #[test]
    fn win_pointer_struct_sizes_match_win32_abi() {
        if std::mem::size_of::<usize>() == 8 {
            assert_eq!(std::mem::size_of::<WinPointerInfo>(), 96);
            assert_eq!(std::mem::size_of::<WinPointerTouchInfo>(), 144);
        } else if std::mem::size_of::<usize>() == 4 {
            assert_eq!(std::mem::size_of::<WinPointerInfo>(), 88);
            assert_eq!(std::mem::size_of::<WinPointerTouchInfo>(), 136);
        }
    }

    #[test]
    fn tracker_preserves_other_active_contacts_and_cancels_cleanly() {
        let mut tracker = TouchTracker::default();
        let down1 = TouchContacts {
            contacts: vec![TouchContact {
                id: 101,
                phase: TouchDown.into(),
                x: 100,
                y: 200,
                width: 12,
                height: 12,
                pressure: 600,
                ..Default::default()
            }],
            ..Default::default()
        };
        let f1 = tracker.build_frame(&down1);
        assert_eq!(f1.len(), 1);
        assert_eq!(
            f1[0].pointer_info.pointer_flags,
            POINTER_FLAG_DOWN | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT
        );

        let down2 = TouchContacts {
            contacts: vec![TouchContact {
                id: 102,
                phase: TouchDown.into(),
                x: 300,
                y: 400,
                ..Default::default()
            }],
            ..Default::default()
        };
        let f2 = tracker.build_frame(&down2);
        assert_eq!(f2.len(), 2);
        assert!(f2.iter().any(|p| p.pointer_info.pointer_id == 0
            && p.pointer_info.pointer_flags
                == (POINTER_FLAG_UPDATE | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT)));
        assert!(f2.iter().any(|p| p.pointer_info.pointer_id == 1
            && p.pointer_info.pointer_flags
                == (POINTER_FLAG_DOWN | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT)));

        let cancel1 = TouchContacts {
            contacts: vec![TouchContact {
                id: 101,
                phase: TouchCancel.into(),
                x: 100,
                y: 200,
                ..Default::default()
            }],
            ..Default::default()
        };
        let f3 = tracker.build_frame(&cancel1);
        assert_eq!(f3.len(), 2);
        assert!(f3.iter().any(|p| p.pointer_info.pointer_id == 0
            && p.pointer_info.pointer_flags == (POINTER_FLAG_UP | POINTER_FLAG_CANCELED)));

        let cleared = tracker.clear_frame();
        assert_eq!(cleared.len(), 1);
        assert_eq!(cleared[0].pointer_info.pointer_id, 1);
        assert!(tracker.clear_frame().is_empty());
    }
}
