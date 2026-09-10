# Load only Zeek's connection logger. This records connection metadata rather
# than packet contents or application payloads.
@load base/protocols/conn

redef LogAscii::use_json = T;
redef Log::default_rotation_interval = 0secs;

event zeek_init()
    {
    local filter = Log::get_filter(Conn::LOG, "default");
    filter$path = "network";
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
