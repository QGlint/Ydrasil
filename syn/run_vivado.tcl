# Batch Vivado synthesis/implementation driver for the Ydrasil FPGA project.

proc usage {} {
    puts "usage: vivado -mode batch -source syn/run_vivado.tcl -tclargs ?options?"
    puts "  -xpr <path>             Vivado project, default FPGA/Ydrasil_FPGA.xpr"
    puts "  -sources_tcl <path>     generated source sync Tcl"
    puts "  -report_dir <path>      report output directory"
    puts "  -jobs <n>               Vivado launch job count"
    puts "  -run_to <synth|route|bitstream|sync_only>"
    puts "  -sync_sources <0|1>     remove old hw/ip sources and add generated list"
    puts "  -force <0|1>            reset runs before launching"
}

proc arg_value {name default_value} {
    global argv
    set idx [lsearch -exact $argv $name]
    if {$idx < 0} {
        return $default_value
    }
    set val_idx [expr {$idx + 1}]
    if {$val_idx >= [llength $argv]} {
        error "missing value for $name"
    }
    return [lindex $argv $val_idx]
}

proc safe_param {name value} {
    if {[catch {set_param $name $value} msg]} {
        puts "warning: could not set_param $name $value: $msg"
    }
}

proc clamp_int {value min_value max_value} {
    if {$value < $min_value} {
        return $min_value
    }
    if {$value > $max_value} {
        return $max_value
    }
    return $value
}

proc remove_hw_ip_sources {} {
    set fs [get_filesets sources_1]
    set stale [list]
    foreach f [get_files -of_objects $fs] {
        set nf [file normalize $f]
        if {[regexp {/(hw/ip)/(jyd_fpga|ydrasil_core|ydrmem|Xilinx_ip_wrapper)/.*\.(sv|v|svh|vh)$} $nf]} {
            lappend stale $f
        }
    }
    if {[llength $stale] > 0} {
        puts "Removing [llength $stale] existing hw/ip RTL/header files from sources_1"
        remove_files -fileset $fs $stale
    }
}

proc assert_run_ok {run_name} {
    set status [get_property STATUS [get_runs $run_name]]
    puts "$run_name status: $status"
    if {[regexp -nocase {fail|error} $status]} {
        error "$run_name failed: $status"
    }
}

proc ensure_dir {dir_name} {
    file mkdir $dir_name
    return [file normalize $dir_name]
}

proc report_if_possible {description command} {
    puts "Writing $description"
    if {[catch {uplevel 1 $command} msg]} {
        puts "warning: failed to write $description: $msg"
    }
}

if {[lsearch -exact $argv "-help"] >= 0 || [lsearch -exact $argv "--help"] >= 0} {
    usage
    exit 0
}

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]

set xpr [file normalize [arg_value "-xpr" [file join $repo_root "FPGA/Ydrasil_FPGA.xpr"]]]
set sources_tcl [file normalize [arg_value "-sources_tcl" [file join $repo_root "build/syn/vivado_sources.tcl"]]]
set report_dir [ensure_dir [arg_value "-report_dir" [file join $repo_root "build/syn/reports"]]]
set checkpoint_dir [ensure_dir [arg_value "-checkpoint_dir" [file join $repo_root "build/syn/checkpoints"]]]
set jobs [arg_value "-jobs" "16"]
set run_to [arg_value "-run_to" "route"]
set sync_sources [arg_value "-sync_sources" "1"]
set force_runs [arg_value "-force" "1"]

if {![file exists $xpr]} {
    error "Vivado project not found: $xpr"
}
if {$sync_sources && ![file exists $sources_tcl]} {
    error "generated sources Tcl not found: $sources_tcl"
}

puts "Opening project: $xpr"
puts "Vivado jobs: $jobs"
puts "Run target: $run_to"
open_project $xpr

set max_threads [clamp_int $jobs 1 32]
if {$max_threads != $jobs} {
    puts "Vivado general.maxThreads is limited to $max_threads; launch_runs still uses -jobs $jobs"
}
safe_param general.maxThreads $max_threads
catch {set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]}

if {$sync_sources} {
    remove_hw_ip_sources
    puts "Sourcing generated sources: $sources_tcl"
    source $sources_tcl
}

set_property top jyd_fpga [get_filesets sources_1]
update_compile_order -fileset sources_1

if {$run_to eq "sync_only"} {
    puts "Source synchronization complete."
    close_project
    exit 0
}

if {[llength [get_ips -quiet]] > 0} {
    puts "Refreshing IP output products"
    report_ip_status -file [file join $report_dir "ip_status.rpt"]
    catch {upgrade_ip [get_ips]}
    generate_target all [get_ips]
}

if {$force_runs} {
    puts "Resetting synth_1"
    reset_run synth_1
}
set_property strategy Flow_AreaOptimized_high [get_runs synth_1]
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
assert_run_ok synth_1

open_run synth_1 -name synth_1
report_if_possible "post-synthesis utilization" \
    "report_utilization -hierarchical -file [file join $report_dir synth_utilization_hier.rpt]"
report_if_possible "post-synthesis timing summary" \
    "report_timing_summary -delay_type max -max_paths 50 -report_unconstrained -file [file join $report_dir synth_timing_summary.rpt]"
report_if_possible "post-synthesis methodology" \
    "report_methodology -file [file join $report_dir synth_methodology.rpt]"
report_if_possible "post-synthesis DRC" \
    "report_drc -file [file join $report_dir synth_drc.rpt]"
write_checkpoint -force [file join $checkpoint_dir synth_1.dcp]

if {$run_to eq "synth"} {
    close_project
    exit 0
}

if {$force_runs} {
    puts "Resetting impl_1"
    reset_run impl_1
}

if {$run_to eq "bitstream"} {
    launch_runs impl_1 -jobs $jobs
} elseif {$run_to eq "route" || $run_to eq "impl"} {
    launch_runs impl_1 -to_step route_design -jobs $jobs
} else {
    error "unknown -run_to value: $run_to"
}
wait_on_run impl_1
assert_run_ok impl_1

open_run impl_1 -name impl_1
report_if_possible "post-route timing summary" \
    "report_timing_summary -delay_type max -max_paths 100 -report_unconstrained -check_timing_verbose -file [file join $report_dir post_route_timing_summary.rpt]"
report_if_possible "post-route timing paths" \
    "report_timing -delay_type max -sort_by group -max_paths 200 -nworst 10 -input_pins -file [file join $report_dir post_route_timing_paths.rpt]"
report_if_possible "post-route utilization" \
    "report_utilization -hierarchical -file [file join $report_dir post_route_utilization_hier.rpt]"
report_if_possible "route status" \
    "report_route_status -file [file join $report_dir post_route_status.rpt]"
report_if_possible "post-route DRC" \
    "report_drc -file [file join $report_dir post_route_drc.rpt]"
report_if_possible "post-route methodology" \
    "report_methodology -file [file join $report_dir post_route_methodology.rpt]"
report_if_possible "post-route design analysis" \
    "report_design_analysis -timing -logic_level_distribution -file [file join $report_dir post_route_design_analysis.rpt]"
report_if_possible "QoR suggestions" \
    "report_qor_suggestions -file [file join $report_dir post_route_qor_suggestions.rpt]"
write_checkpoint -force [file join $checkpoint_dir impl_1_route.dcp]

puts "Reports written to $report_dir"
close_project
