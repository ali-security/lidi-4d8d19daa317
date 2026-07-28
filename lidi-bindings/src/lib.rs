#![allow(unsafe_code)]

use lidi_clients as clients;
use std::{
    ffi::{CStr, c_char},
    net::SocketAddr,
    path::PathBuf,
    ptr,
    str::FromStr,
};

/// Allocates a new sending [`clients::file::Config`] from an `ip:port` C string.
///
/// Returns a raw pointer to the config, or a null pointer if `ptr_addr` is null. The returned
/// pointer must be released with [`diode_free_config`].
///
/// # Panics
///
/// Will panic if `ptr_addr` does not contain a valid `ip:port` address.
#[unsafe(no_mangle)]
#[allow(clippy::missing_safety_doc)]
pub unsafe extern "C" fn diode_new_config(
    ptr_addr: *const c_char,
    buffer_size: u32,
) -> *mut clients::file::Config<clients::DiodeSend> {
    if ptr_addr.is_null() {
        return ptr::null_mut();
    }
    let cstr_addr = unsafe { CStr::from_ptr(ptr_addr) };
    let rust_addr = String::from_utf8_lossy(cstr_addr.to_bytes()).to_string();
    let socket_addr = SocketAddr::from_str(&rust_addr).expect("ip:port");

    let config = Box::new(clients::file::Config {
        diode: clients::DiodeSend::Tcp(socket_addr),
        buffer_size: buffer_size as usize,
        #[cfg(feature = "hash")]
        hash: false,
        max_files: 0,
        overwrite: false,
        tmp_dir: None,
        ignore: None,
        recursive: false,
        watch: false,
        static_watch: false,
        delete: false,
        tls: lidi_clients::Tls::default(),
    });
    Box::into_raw(config)
}

/// Frees a [`clients::file::Config`] previously allocated by [`diode_new_config`]. Does nothing if
/// `ptr` is null.
#[unsafe(no_mangle)]
#[allow(clippy::missing_safety_doc)]
pub unsafe extern "C" fn diode_free_config(ptr: *mut clients::file::Config<clients::DiodeSend>) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        drop(Box::from_raw(ptr));
    }
}

/// Sends the file at `ptr_filepath` through the diode described by `config`.
///
/// Returns the number of bytes sent (0 on any error, including null pointers).
///
/// # Panics
///
/// Will panic if `ptr` is non-null but cannot be dereferenced into a valid `config` reference.
#[unsafe(no_mangle)]
#[allow(clippy::missing_safety_doc)]
pub unsafe extern "C" fn diode_send_file(
    ptr: *mut clients::file::Config<clients::DiodeSend>,
    ptr_filepath: *const c_char,
) -> u32 {
    if ptr.is_null() {
        return 0;
    }
    let config = unsafe { ptr.as_ref() }.expect("config");

    if ptr_filepath.is_null() {
        return 0;
    }
    let cstr_filepath = unsafe { CStr::from_ptr(ptr_filepath) };
    let rust_filepath =
        PathBuf::from(String::from_utf8_lossy(cstr_filepath.to_bytes()).to_string());

    let result: usize =
        clients::file::send::send_entry(config, rust_filepath.as_path(), None).unwrap_or(0);
    u32::try_from(result).unwrap_or(0)
}

/// Receives files into the `ptr_odir` output directory.
///
/// Uses the endpoint address stored in `config` as the source to accept the connection from
/// `lidi-receive`. Does nothing if a pointer argument is null.
///
/// # Panics
///
/// Will panic if `ptr` is non-null but cannot be dereferenced into a valid `config` reference.
#[unsafe(no_mangle)]
#[allow(clippy::missing_safety_doc)]
pub unsafe extern "C" fn diode_receive_files(
    ptr: *mut clients::file::Config<clients::DiodeSend>,
    ptr_odir: *const c_char,
) {
    if ptr.is_null() {
        return;
    }
    let config = unsafe { ptr.as_ref() }.expect("config");

    let (from_tcp, from_tls, from_unix) = match &config.diode {
        clients::DiodeSend::Tcp(socket_addr) => (Some(*socket_addr), None, None),
        clients::DiodeSend::Tls(socket_addr) => (None, Some(*socket_addr), None),
        clients::DiodeSend::Unix(path) => (None, None, Some(path.clone())),
    };

    let config = clients::file::Config {
        diode: clients::DiodeReceive {
            from_tcp,
            from_tls,
            from_unix,
        },
        buffer_size: config.buffer_size,
        #[cfg(feature = "hash")]
        hash: false,
        max_files: 0,
        overwrite: false,
        tmp_dir: None,
        ignore: None,
        recursive: false,
        watch: false,
        static_watch: false,
        delete: config.delete,
        tls: config.tls.clone(),
    };

    if ptr_odir.is_null() {
        return;
    }
    let cstr_odir = unsafe { CStr::from_ptr(ptr_odir) };
    let rust_odir = String::from_utf8_lossy(cstr_odir.to_bytes()).to_string();
    let odir = PathBuf::from(rust_odir);

    let _ = clients::file::receive::receive_files(&config, &odir);
}
