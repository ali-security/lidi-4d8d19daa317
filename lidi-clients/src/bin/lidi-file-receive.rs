use clap::Parser;
use std::{net, os::unix::ffi::OsStrExt, path};

#[derive(clap::Args)]
#[group(required = true, multiple = false)]
#[allow(clippy::struct_field_names)]
struct Listeners {
    #[clap(
        value_name = "ip:port",
        long,
        help = "IP address and port to accept TCP connections from lidi-receive"
    )]
    from_tcp: Option<net::SocketAddr>,
    #[clap(
        value_name = "ip:port",
        long,
        help = "IP address and port to accept TLS connections from lidi-receive"
    )]
    from_tls: Option<net::SocketAddr>,
    #[clap(
        value_name = "path",
        long,
        help = "Path of Unix socket to accept Unix connections from lidi-receive"
    )]
    from_unix: Option<path::PathBuf>,
}

#[derive(clap::Args)]
struct WriteOptions {
    #[clap(long, help = "Overwrite existing files")]
    overwrite: bool,
    #[clap(
        long,
        help = "Directory where to store files during their transfer.",
        long_help = "Directory where to store files during their transfer, before being moved to the
output directory. Allows to detect the end of file transfers without using
inotify, and to avoid having incomplete files in the output directory."
    )]
    tmp_dir: Option<path::PathBuf>,
}

#[derive(Parser)]
#[clap(about = "Receive file(s) sent by lidi-file-send through lidi.")]
struct Args {
    #[clap(
        default_value = "Info",
        value_name = "Off|Error|Warn|Info|Debug|Trace",
        long,
        help = "Log level"
    )]
    log_level: log::LevelFilter,
    #[clap(long, help = "Path to log4rs configuration file")]
    log_config: Option<path::PathBuf>,
    #[clap(flatten)]
    from: Listeners,
    #[clap(
        default_value = "4194304",
        value_name = "bytes",
        long,
        help = "Size of client write buffer"
    )]
    buffer_size: usize,
    #[cfg(feature = "hash")]
    #[clap(long, help = "Verify the hash of file content")]
    hash: bool,
    #[clap(
        long,
        default_value = "0",
        value_name = "max_files",
        help = "Exits after receiving max_files files"
    )]
    max_files: usize,
    #[clap(flatten)]
    write_options: WriteOptions,
    #[clap(flatten)]
    tls: lidi_clients::Tls,
    #[clap(long, help = "Chroot in output directory before receiving files")]
    chroot: bool,
    #[clap(default_value = ".", help = "Output directory")]
    output_directory: path::PathBuf,
}

fn main() {
    let args = Args::parse();

    if let Err(e) = lidi_clients::init_logger(args.log_level, args.log_config.as_ref()) {
        eprintln!("failed to initialize logger: {e}");
        std::process::exit(1);
    }

    if args.buffer_size == 0 {
        eprintln!("buffer_size must be greater than 0");
        std::process::exit(1);
    }

    log::info!(
        "{} version {}",
        env!("CARGO_PKG_NAME"),
        env!("CARGO_PKG_VERSION")
    );

    let diode = lidi_clients::DiodeReceive {
        from_tcp: args.from.from_tcp,
        from_tls: args.from.from_tls,
        from_unix: args.from.from_unix,
    };

    let config = lidi_clients::file::Config {
        diode,
        buffer_size: args.buffer_size,
        #[cfg(feature = "hash")]
        hash: args.hash,
        max_files: args.max_files,
        overwrite: args.write_options.overwrite,
        tmp_dir: args.write_options.tmp_dir,
        ignore: None,
        recursive: false,
        watch: false,
        tls: args.tls,
        delete: false,
    };

    let output_directory = if args.chroot {
        let mut bytes_output_directory = Vec::from(args.output_directory.as_os_str().as_bytes());
        bytes_output_directory.push(0);

        let c_output_directory = match std::ffi::CString::from_vec_with_nul(bytes_output_directory)
        {
            Ok(res) => res,
            Err(e) => {
                log::error!(
                    "failed to convert output directory to C string {}: {e}",
                    args.output_directory.display()
                );
                std::process::exit(1);
            }
        };

        if unsafe { libc::chroot(c_output_directory.as_ptr()) } != 0 {
            #[cfg(not(target_os = "freebsd"))]
            let errno = unsafe { *libc::__errno_location() };
            #[cfg(target_os = "freebsd")]
            let errno = unsafe { *libc::__error() };
            let err_str =
                unsafe { std::ffi::CStr::from_ptr(libc::strerror(errno)) }.to_string_lossy();
            log::error!(
                "failed to chroot in {}: {err_str}",
                args.output_directory.display()
            );
            std::process::exit(1);
        }

        log::info!("chrooted in {}", args.output_directory.display());

        path::PathBuf::from("/")
    } else {
        args.output_directory
    };

    if let Err(e) = lidi_clients::file::receive::receive_files(&config, &output_directory) {
        log::error!("{e}");
        std::process::exit(1);
    }
}
