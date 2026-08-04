# Compatibility entry point for the original jyd_fpga board top.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]

if {[lsearch -exact $argv "-top"] < 0} {
    lappend argv -top jyd_fpga
}
if {[lsearch -exact $argv "-legacy_ip"] < 0} {
    lappend argv -legacy_ip 1
}
if {[lsearch -exact $argv "-sources_tcl"] < 0} {
    lappend argv -sources_tcl [file join $repo_root \
        "build/syn/vivado_sources_jyd_fpga.tcl"]
}

source [file join $script_dir "run_vivado.tcl"]
