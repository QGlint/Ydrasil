# Pin-free Vivado out-of-context synthesis for one RTL top.

proc arg_value {name default_value} {
    global argv
    set idx [lsearch -exact $argv $name]
    if {$idx < 0} { return $default_value }
    if {$idx + 1 >= [llength $argv]} { error "missing value for $name" }
    return [lindex $argv [expr {$idx + 1}]]
}

set flist [file normalize [arg_value -flist ""]]
set top [arg_value -top "ydrasil_core"]
set part [arg_value -part "xc7k325tffg900-2"]
set out_dir [file normalize [arg_value -out_dir "build/vivado-ooc"]]
if {$flist eq "" || ![file exists $flist]} { error "RTL file list not found: $flist" }
file mkdir $out_dir

set sources [list]
set include_dirs [list]
set defines [list]
set fp [open $flist r]
while {[gets $fp line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string match "#*" $line]} { continue }
    if {[string match "+incdir+*" $line]} {
        lappend include_dirs [string range $line 8 end]
    } elseif {[string match "+define+*" $line]} {
        lappend defines [string range $line 8 end]
    } else {
        lappend sources [file normalize $line]
    }
}
close $fp

create_project -in_memory -part $part
set fs [current_fileset]
if {[llength $include_dirs] > 0} { set_property include_dirs $include_dirs $fs }
if {[llength $defines] > 0} { set_property verilog_define $defines $fs }
read_verilog -sv $sources
set_property top $top $fs
update_compile_order -fileset $fs

# Out-of-context mode deliberately has no XDC or package pins.  It answers
# elaboration, inferred-resource and local timing questions for the module.
synth_design -top $top -part $part -mode out_of_context
catch {report_utilization -hierarchical -file [file join $out_dir utilization.rpt]}
catch {report_timing_summary -file [file join $out_dir timing_summary.rpt]}
catch {report_timing -max_paths 50 -file [file join $out_dir timing_paths.rpt]}
write_checkpoint -force [file join $out_dir ${top}_ooc.dcp]
close_project
puts "Vivado OOC complete: top=$top part=$part output=$out_dir"
