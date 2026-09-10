##! Local site policy for the SPE. This file will go into
##! /opt/zeek/share/zeek/site/local.zeek, replacing the stock one.
##!
##! ZeekControl loads it automatically (SitePolicyScripts in zeekctl.cfg) on
##! top of Zeek's default script set. The SPE records who talked to whom, not
##! what was said: one line per connection, no payload inspection.

# Cloud virtual network cards compute outgoing checksums after the capture
# point. Without this, Zeek discards the VM's own outbound packets as corrupt.
redef ignore_checksums = T;

# One JSON object per line instead of Zeek's tab-separated default. Set to F
# for the classic TSV format with a #fields header.
redef LogAscii::use_json = T;

# Rotation belongs to ZeekControl: LogRotationInterval in zeekctl.cfg overrides
# Log::default_rotation_interval, and each rotated file is moved, compressed,
# into LogDir/YYYY-MM-DD/. Do not redef the interval here.

event zeek_init()
    {
    local filter = Log::get_filter(Conn::LOG, "default");
    # Output file name without the .log extension: network -> network.log.
    filter$path = "network";
    # The fields kept. Everything else in Conn::Info is dropped. The two most
    # useful ones left out are "service" (protocol guessed from the port and
    # payload) and "history" (the packet-level story of the connection).
    filter$include = set(
        "ts",
        "uid",
        "id.orig_h",
        "id.orig_p",
        "id.resp_h",
        "id.resp_p",
        "proto",
        "duration",
        "orig_bytes",
        "resp_bytes",
        "conn_state",
        "orig_pkts",
        "resp_pkts",
        "orig_ip_bytes",
        "resp_ip_bytes"
    );
    Log::add_filter(Conn::LOG, filter);
    }

# Zeek's default scripts would also write dns.log, ssl.log, http.log, files.log,
# weird.log and more. Keep only the connection log. Runs after every stream has
# been created (they are created at priority 0 and above). Delete this handler
# to get the standard set of logs back; each one then appears next to
# network.log and is archived the same way.
event zeek_init() &priority=-10
    {
    local to_disable: set[Log::ID];
    for ( id in Log::active_streams )
        {
        if ( id != Conn::LOG )
            add to_disable[id];
        }
    for ( id in to_disable )
        Log::disable_stream(id);
    }
