# Batch Vivado synthesis/implementation driver for the Ydrasil FPGA project.

proc usage {} {
    puts "usage: vivado -mode batch -source syn/run_vivado.tcl -tclargs ?options?"
    puts "  -xpr <path>             Vivado project, default FPGA/Ydrasil_FPGA.xpr"
    puts "  -sources_tcl <path>     generated source sync Tcl"
    puts "  -report_dir <path>      report output directory"
    puts "  -jobs <n>               Vivado launch job count"
    puts "  -run_to <synth|route|bitstream|reports|sync_only>"
    puts "  -sync_sources <0|1>     remove old hw/ip sources and add generated list"
    puts "  -force <0|1>            reset runs before launching"
    puts "  -pll_freq_mhz <mhz>     RTL MMCM CPU clock frequency selected by synthesis define, default 150"
    puts "  -artifact_dir <path>    copied bitstream/artifact output directory"
    puts "  -timing_summary_max_paths <n>  timing summary path limit, default 1000"
    puts "  -timing_path_max_paths <n>     violating report_timing path limit, default 500"
    puts "  -timing_nworst <n>             report_timing nworst per endpoint/group, default 100"
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

proc configure_performance_implementation {run_name} {
    set run [get_runs $run_name]
    set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE Explore $run
    set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore $run
    set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $run
    set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE ExploreWithHoldFix $run
    set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore $run
    set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true $run
    set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $run
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

proc remove_missing_sources {} {
    foreach fs_name {sources_1 constrs_1 sim_1} {
        set fs [get_filesets -quiet $fs_name]
        if {[llength $fs] == 0} {
            continue
        }
        set missing [list]
        foreach f [get_files -of_objects $fs] {
            set nf [file normalize $f]
            if {![file exists $nf]} {
                lappend missing $f
            }
        }
        if {[llength $missing] > 0} {
            puts "Removing [llength $missing] missing files from $fs_name"
            remove_files -fileset $fs $missing
        }
    }
}

proc remove_legacy_pll_ip {} {
    set pll_files [get_files -quiet -all */pll.xci]
    if {[llength $pll_files] > 0} {
        puts "Removing legacy clk_wiz pll IP from staged project; RTL MMCM clocking is used instead"
        remove_files $pll_files
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

proc clocks_near_period {target_period tolerance} {
    set result [list]
    foreach clk [get_clocks -quiet *] {
        set period [get_property PERIOD $clk]
        if {$period eq ""} {
            continue
        }
        if {[expr {abs(double($period) - double($target_period)) <= double($tolerance)}]} {
            lappend result $clk
        }
    }
    return $result
}

proc cpu_clocks_near_period {target_period tolerance} {
    set candidates [clocks_near_period $target_period $tolerance]
    set cpu_clocks [list]
    foreach clk $candidates {
        set name [get_property NAME $clk]
        if {[regexp -nocase {cpu|clk_out2} $name]} {
            lappend cpu_clocks $clk
        }
    }
    if {[llength $cpu_clocks] > 0} {
        return $cpu_clocks
    }
    return $candidates
}

proc freq_file_tag {freq_mhz} {
    set tag [string trim $freq_mhz]
    if {![regexp {^[0-9]+([.][0-9]+)?$} $tag]} {
        error "invalid frequency for report tag: $freq_mhz"
    }
    return [string map {. p} $tag]
}

proc report_cpu_freq_timing {report_dir freq_mhz} {
    global timing_summary_max_paths timing_path_max_paths timing_nworst

    set target_period [expr {1000.0 / double($freq_mhz)}]
    set tag [freq_file_tag $freq_mhz]
    set cpu_clocks [cpu_clocks_near_period $target_period 0.0500]
    set out [file join $report_dir "cpu${tag}_clocks.rpt"]
    set fp [open $out w]
    puts $fp "$freq_mhz MHz candidate clocks, selected by period ~= [format %.4f $target_period] ns"
    foreach clk $cpu_clocks {
        puts $fp "[get_property NAME $clk] period=[get_property PERIOD $clk] waveform=[get_property WAVEFORM $clk]"
    }
    close $fp

    if {[llength $cpu_clocks] == 0} {
        puts "warning: no $freq_mhz MHz candidate clock found"
        return
    }

    puts "Writing $freq_mhz MHz timing summary"
    if {[catch {
        report_timing_summary -delay_type max -max_paths $timing_summary_max_paths -report_unconstrained \
            -file [file join $report_dir cpu${tag}_timing_summary.rpt]
    } msg]} {
        puts "warning: failed to write $freq_mhz MHz timing summary: $msg"
    }
    puts "Writing $freq_mhz MHz violating timing paths"
    if {[catch {
        report_timing -delay_type max -from $cpu_clocks -to $cpu_clocks -sort_by slack \
            -slack_lesser_than 0.000 -max_paths $timing_path_max_paths -nworst $timing_nworst \
            -input_pins -file [file join $report_dir cpu${tag}_timing_violations.rpt]
    } msg]} {
        puts "warning: failed to write $freq_mhz MHz violating timing paths: $msg"
    }
    puts "Writing $freq_mhz MHz intra-clock timing paths"
    if {[catch {
        report_timing -delay_type max -from $cpu_clocks -to $cpu_clocks -sort_by slack \
            -slack_lesser_than 0.000 -max_paths $timing_path_max_paths -nworst $timing_nworst \
            -input_pins -file [file join $report_dir cpu${tag}_timing_paths.rpt]
    } msg]} {
        puts "warning: failed to write $freq_mhz MHz intra-clock timing paths: $msg"
    }
}

proc validate_clocking_frequency {freq_mhz} {
    set freq_mhz [string trim $freq_mhz]
    if {![regexp {^[0-9]+([.][0-9]+)?$} $freq_mhz] || double($freq_mhz) <= 0.0} {
        error "invalid -pll_freq_mhz value: $freq_mhz"
    }

    set pll_ip [get_ips -quiet pll]
    if {[llength $pll_ip] == 0} {
        puts "Using RTL MMCM clocking configured by synthesis define for ${freq_mhz} MHz CPU clock"
        return
    }

    puts "Leaving existing pll clk_wiz IP unchanged; RTL MMCM clocking is selected by synthesis defines"
    report_property $pll_ip -file [file join $::report_dir pll_properties.rpt]
}

proc copy_existing_files {patterns dest_dir} {
    set copied [list]
    foreach pattern $patterns {
        foreach src [glob -nocomplain $pattern] {
            if {[file isfile $src]} {
                set dst [file join $dest_dir [file tail $src]]
                file copy -force $src $dst
                lappend copied $dst
            }
        }
    }
    return $copied
}

proc archive_run_artifacts {run_name artifact_dir pll_freq_mhz run_to report_dir checkpoint_dir run_dir top_name} {
    set artifact_dir [ensure_dir $artifact_dir]
    if {$run_dir eq ""} {
        set run_obj [get_runs -quiet $run_name]
        if {[llength $run_obj] > 0} {
            set run_dir [get_property DIRECTORY $run_obj]
        }
    }
    if {$top_name eq ""} {
        set top_name [get_property top [get_filesets sources_1]]
    }
    if {$run_dir eq "" || ![file exists $run_dir]} {
        puts "warning: run directory for $run_name not found; only checkpoint_dir artifacts will be archived"
    }

    set patterns [list \
        [file join $run_dir "${top_name}.bit"] \
        [file join $run_dir "${top_name}*.bit"] \
        [file join $run_dir "${top_name}*.ltx"] \
        [file join $run_dir "${top_name}_routed.dcp"] \
        [file join $checkpoint_dir "impl_1_route.dcp"] \
        [file join $checkpoint_dir "synth_1.dcp"]]
    set copied [copy_existing_files $patterns $artifact_dir]
    if {$run_to eq "bitstream" && [llength [glob -nocomplain [file join $artifact_dir "*.bit"]]] == 0} {
        error "bitstream run completed but no .bit file was copied from $run_dir to $artifact_dir"
    }

    set fp [open [file join $artifact_dir "manifest.txt"] w]
    puts $fp "pll_freq_mhz=$pll_freq_mhz"
    puts $fp "run_to=$run_to"
    puts $fp "xpr=[current_project]"
    puts $fp "run_dir=$run_dir"
    puts $fp "report_dir=$report_dir"
    puts $fp "checkpoint_dir=$checkpoint_dir"
    puts $fp "copied_files:"
    foreach f $copied {
        puts $fp "  $f"
    }
    close $fp
    puts "Artifacts written to $artifact_dir"
}

proc open_impl_design {run_name checkpoint_dir} {
    set opened 0
    if {![catch {open_run $run_name -name $run_name} msg]} {
        set opened 1
    } else {
        puts "warning: open_run $run_name failed: $msg"
    }

    if {$opened} {
        return
    }

    set run_obj [get_runs $run_name]
    set run_dir [get_property DIRECTORY $run_obj]
    set top_name [get_property top [get_filesets sources_1]]
    set candidates [list \
        [file join $run_dir "${top_name}_routed.dcp"] \
        [file join $run_dir "${top_name}.dcp"] \
        [file join $checkpoint_dir "impl_1_route.dcp"]]

    foreach dcp $candidates {
        if {[file exists $dcp]} {
            puts "Opening routed checkpoint: $dcp"
            open_checkpoint $dcp
            return
        }
    }

    error "could not open $run_name and no routed checkpoint found in: $candidates"
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
set artifact_dir [ensure_dir [arg_value "-artifact_dir" [file join $repo_root "build/syn/artifacts"]]]
set jobs [arg_value "-jobs" "16"]
set run_to [arg_value "-run_to" "route"]
set sync_sources [arg_value "-sync_sources" "1"]
set force_runs [arg_value "-force" "1"]
set pll_freq_mhz [arg_value "-pll_freq_mhz" "150"]
set timing_summary_max_paths [arg_value "-timing_summary_max_paths" "1000"]
set timing_path_max_paths [arg_value "-timing_path_max_paths" "500"]
set timing_nworst [arg_value "-timing_nworst" "100"]

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

remove_missing_sources
remove_legacy_pll_ip

if {$sync_sources} {
    remove_hw_ip_sources
    puts "Sourcing generated sources: $sources_tcl"
    source $sources_tcl
}

set_property top jyd_fpga [get_filesets sources_1]
update_compile_order -fileset sources_1

if {$run_to eq "sync_only"} {
    validate_clocking_frequency $pll_freq_mhz
    puts "Source synchronization complete."
    close_project
    exit 0
}

if {[llength [get_ips -quiet]] > 0} {
    puts "Refreshing IP output products"
    report_ip_status -file [file join $report_dir "ip_status.rpt"]
    catch {upgrade_ip [get_ips]}
    validate_clocking_frequency $pll_freq_mhz
    generate_target all [get_ips]
}

if {$run_to eq "reports"} {
    open_impl_design impl_1 $checkpoint_dir
    report_if_possible "post-route timing summary" \
        "report_timing_summary -delay_type max -max_paths $timing_summary_max_paths -report_unconstrained -check_timing_verbose -file [file join $report_dir post_route_timing_summary.rpt]"
    report_if_possible "post-route violating timing paths" \
        "report_timing -delay_type max -sort_by slack -slack_lesser_than 0.000 -max_paths $timing_path_max_paths -nworst $timing_nworst -input_pins -file [file join $report_dir post_route_timing_violations.rpt]"
    report_if_possible "post-route timing paths" \
        "report_timing -delay_type max -sort_by slack -slack_lesser_than 0.000 -max_paths $timing_path_max_paths -nworst $timing_nworst -input_pins -file [file join $report_dir post_route_timing_paths.rpt]"
    report_if_possible "post-route clocks" \
        "report_clocks -file [file join $report_dir post_route_clocks.rpt]"
    report_if_possible "post-route clock interaction" \
        "report_clock_interaction -delay_type max -file [file join $report_dir post_route_clock_interaction.rpt]"
    report_if_possible "post-route check timing" \
        "check_timing -verbose -file [file join $report_dir post_route_check_timing.rpt]"
    report_cpu_freq_timing $report_dir $pll_freq_mhz
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
    exit 0
}

if {$force_runs} {
    foreach child_run [get_runs -quiet *synth*] {
        if {[get_property NAME $child_run] ne "synth_1"} {
            puts "Resetting [get_property NAME $child_run]"
            reset_run $child_run
        }
    }
    puts "Resetting synth_1"
    reset_run synth_1
}
set_property strategy Flow_AreaOptimized_high [get_runs synth_1]
configure_performance_implementation impl_1
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
assert_run_ok synth_1

open_run synth_1 -name synth_1
report_if_possible "post-synthesis utilization" \
    "report_utilization -hierarchical -file [file join $report_dir synth_utilization_hier.rpt]"
report_if_possible "post-synthesis timing summary" \
    "report_timing_summary -delay_type max -max_paths 50 -report_unconstrained -file [file join $report_dir synth_timing_summary.rpt]"
report_if_possible "post-synthesis clocks" \
    "report_clocks -file [file join $report_dir synth_clocks.rpt]"
report_cpu_freq_timing $report_dir $pll_freq_mhz
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
    launch_runs impl_1 -to_step write_bitstream -jobs $jobs
} elseif {$run_to eq "route" || $run_to eq "impl"} {
    launch_runs impl_1 -to_step route_design -jobs $jobs
} else {
    error "unknown -run_to value: $run_to"
}
wait_on_run impl_1
assert_run_ok impl_1

set impl_run_dir ""
set top_name [get_property top [get_filesets sources_1]]
set impl_run_obj [get_runs -quiet impl_1]
if {[llength $impl_run_obj] > 0} {
    set impl_run_dir [get_property DIRECTORY $impl_run_obj]
}

open_impl_design impl_1 $checkpoint_dir
report_if_possible "post-route timing summary" \
    "report_timing_summary -delay_type max -max_paths $timing_summary_max_paths -report_unconstrained -check_timing_verbose -file [file join $report_dir post_route_timing_summary.rpt]"
report_if_possible "post-route violating timing paths" \
    "report_timing -delay_type max -sort_by slack -slack_lesser_than 0.000 -max_paths $timing_path_max_paths -nworst $timing_nworst -input_pins -file [file join $report_dir post_route_timing_violations.rpt]"
report_if_possible "post-route timing paths" \
    "report_timing -delay_type max -sort_by slack -slack_lesser_than 0.000 -max_paths $timing_path_max_paths -nworst $timing_nworst -input_pins -file [file join $report_dir post_route_timing_paths.rpt]"
report_if_possible "post-route clocks" \
    "report_clocks -file [file join $report_dir post_route_clocks.rpt]"
report_if_possible "post-route clock interaction" \
    "report_clock_interaction -delay_type max -file [file join $report_dir post_route_clock_interaction.rpt]"
report_if_possible "post-route check timing" \
    "check_timing -verbose -file [file join $report_dir post_route_check_timing.rpt]"
report_cpu_freq_timing $report_dir $pll_freq_mhz
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
archive_run_artifacts impl_1 $artifact_dir $pll_freq_mhz $run_to $report_dir $checkpoint_dir $impl_run_dir $top_name

puts "Reports written to $report_dir"
close_project
