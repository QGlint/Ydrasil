# Batch Vivado synthesis/implementation driver for the Ydrasil FPGA project.

proc usage {} {
    puts "usage: vivado -mode batch -source syn/run_vivado.tcl -tclargs ?options?"
    puts "  -xpr <path>             Vivado project, default FPGA/Ydrasil_FPGA.xpr"
    puts "  -sources_tcl <path>     generated source sync Tcl"
    puts "  -report_dir <path>      report output directory"
    puts "  -jobs <n>               Vivado launch job count"
    puts "  -threads_per_run <n>    max threads used by each Vivado process"
    puts "  -impl_runs <n>          parallel implementation run count, default 1"
    puts "  -impl_mode <sweep|extreme>  implementation tuning mode, default sweep"
    puts "  -run_to <synth|route|bitstream|reports|sync_only>"
    puts "  -sync_sources <0|1>     remove old hw/ip sources and add generated list"
    puts "  -force <0|1>            reset runs before launching"
    puts "  -pll_freq_mhz <mhz>     200 selects pll IP; other supported frequencies select RTL MMCM"
    puts "  -board_xdc <path>       overlay board-specific constraints after platform constraints"
    puts "  -enable_ila <0|1>       create ila_board for the conditional board probes"
    puts "  -irom_coe <path>        IROM initialization file for this build"
    puts "  -dram_coe <path>        DRAM initialization file for this build"
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

proc configure_sweep_implementation {run_name strategy} {
    set run [get_runs $run_name]
    set_property strategy $strategy $run
    set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $run
}

proc prepare_implementation_runs {count mode} {
    if {$mode eq "extreme"} {
        configure_performance_implementation impl_1
        return [list impl_1]
    }
    if {$mode ne "sweep"} {
        error "unknown -impl_mode value: $mode"
    }

    set strategies [list \
        Performance_ExtraTimingOpt \
        Performance_Explore \
        Performance_ExplorePostRoutePhysOpt \
        Performance_Retiming \
        Performance_NetDelay_high]
    set count [clamp_int $count 1 [llength $strategies]]
    set runs [list]
    for {set idx 0} {$idx < $count} {incr idx} {
        set run_name [expr {$idx == 0 ? "impl_1" : "impl_sweep_$idx"}]
        if {$idx > 0 && [llength [get_runs -quiet $run_name]] == 0} {
            create_run $run_name -parent_run synth_1 -flow {Vivado Implementation 2024} \
                -strategy [lindex $strategies $idx]
        }
        configure_sweep_implementation $run_name [lindex $strategies $idx]
        lappend runs $run_name
        puts "Implementation sweep: $run_name strategy=[lindex $strategies $idx]"
    }
    return $runs
}

proc select_best_implementation {run_names report_dir checkpoint_dir} {
    set best_run ""
    set best_wns -Inf
    set csv [open [file join $report_dir implementation_sweep.csv] w]
    puts $csv "run,strategy,status,wns_ns"
    foreach run_name $run_names {
        set run [get_runs $run_name]
        set status [get_property STATUS $run]
        set strategy [get_property STRATEGY $run]
        set wns ""
        set completed_with_timing_failure \
            [regexp -nocase {complete.*failed timing} $status]
        if {![regexp -nocase {fail|error} $status] ||
            $completed_with_timing_failure} {
            if {[catch {open_impl_design $run_name $checkpoint_dir} open_msg]} {
                puts "warning: could not evaluate implementation run $run_name: $open_msg"
            } else {
                set worst [get_timing_paths -quiet -delay_type max -max_paths 1 -nworst 1]
                if {[llength $worst] > 0} {
                    set wns [get_property SLACK [lindex $worst 0]]
                    if {$best_run eq "" || double($wns) > double($best_wns)} {
                        set best_run $run_name
                        set best_wns $wns
                    }
                }
                report_timing_summary -delay_type max -report_unconstrained \
                    -file [file join $report_dir ${run_name}_timing_summary.rpt]
                close_design
            }
        }
        set csv_status [string map [list "," ";"] $status]
        puts $csv "$run_name,$strategy,$csv_status,$wns"
        puts "Implementation result: $run_name strategy=$strategy status=$status WNS=$wns"
    }
    close $csv
    if {$best_run eq ""} {
        error "no successful implementation run produced a timing path"
    }
    set fp [open [file join $report_dir best_implementation.txt] w]
    puts $fp "run=$best_run"
    puts $fp "wns_ns=$best_wns"
    puts $fp "strategy=[get_property STRATEGY [get_runs $best_run]]"
    close $fp
    puts "Best implementation: $best_run WNS=$best_wns"
    return $best_run
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

proc configure_board_constraints {board_xdc} {
    if {$board_xdc eq ""} {
        puts "Using platform constraints from the project"
        return
    }
    set board_xdc [file normalize $board_xdc]
    if {![file exists $board_xdc]} {
        error "board constraint file not found: $board_xdc"
    }

    set fs [get_filesets constrs_1]
    puts "Adding board clock override while retaining platform pin constraints: $board_xdc"
    add_files -norecurse -fileset $fs $board_xdc
    set_property PROCESSING_ORDER LATE [get_files -of_objects $fs $board_xdc]
}

proc configure_board_ila {enable_ila} {
    if {!$enable_ila} {
        return
    }
    if {[llength [get_ips -quiet ila_board]] == 0} {
        puts "Creating ila_board with LED and seg_wdata probes"
        create_ip -name ila -vendor xilinx.com -library ip -module_name ila_board
    }
    set_property -dict [list \
        CONFIG.C_NUM_OF_PROBES {2} \
        CONFIG.C_PROBE0_WIDTH {32} \
        CONFIG.C_PROBE1_WIDTH {32} \
        CONFIG.C_DATA_DEPTH {1024} \
        CONFIG.C_ADV_TRIGGER {false} \
        CONFIG.C_INPUT_PIPE_STAGES {0}] [get_ips ila_board]
}

proc configure_memory_coe {ip_name coe_file} {
    set ip [get_ips -quiet $ip_name]
    if {[llength $ip] == 0} {
        error "memory IP not found: $ip_name"
    }
    set coe_file [file normalize $coe_file]
    if {![file exists $coe_file]} {
        error "$ip_name COE file not found: $coe_file"
    }
    puts "Configuring $ip_name initialization: $coe_file"
    set_property -dict [list \
        CONFIG.Load_Init_File {true} \
        CONFIG.Coe_File $coe_file] $ip
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

    if {double($freq_mhz) != 200.0} {
        puts "Using RTL MMCM clocking configured by synthesis define for ${freq_mhz} MHz CPU clock"
        return
    }

    set pll_ip [get_ips -quiet pll]
    if {[llength $pll_ip] == 0} {
        error "200 MHz build requires the pll clk_wiz IP"
    }
    set_property -dict [list \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {50.000} \
        CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {200.000}] $pll_ip
    puts "Using pll clk_wiz IP with 50 MHz peripheral and 200 MHz CPU outputs"
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
    global board_xdc dram_coe enable_ila irom_coe
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
        [file join $checkpoint_dir "best_impl_route.dcp"] \
        [file join $checkpoint_dir "impl_1_route.dcp"] \
        [file join $checkpoint_dir "synth_1.dcp"]]
    set copied [copy_existing_files $patterns $artifact_dir]
    if {$run_to eq "bitstream" && [llength [glob -nocomplain [file join $artifact_dir "*.bit"]]] == 0} {
        error "bitstream run completed but no .bit file was copied from $run_dir to $artifact_dir"
    }

    set fp [open [file join $artifact_dir "manifest.txt"] w]
    puts $fp "pll_freq_mhz=$pll_freq_mhz"
    puts $fp "board_xdc=$board_xdc"
    puts $fp "enable_ila=$enable_ila"
    puts $fp "irom_coe=$irom_coe"
    puts $fp "dram_coe=$dram_coe"
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

proc discover_routed_implementation_runs {} {
    set result [list]
    set top_name [get_property top [get_filesets sources_1]]
    foreach run_obj [get_runs -quiet] {
        set run_name [get_property NAME $run_obj]
        if {![regexp {^impl_(1|sweep_[0-9]+)$} $run_name]} {
            continue
        }
        set routed_dcp [file join [get_property DIRECTORY $run_obj] "${top_name}_routed.dcp"]
        if {[file exists $routed_dcp]} {
            lappend result $run_name
        }
    }
    return [lsort -dictionary $result]
}

proc open_impl_design {run_name checkpoint_dir} {
    set run_obj [get_runs -quiet $run_name]
    if {[llength $run_obj] == 0} {
        error "implementation run not found: $run_name"
    }
    set run_dir [get_property DIRECTORY $run_obj]
    set top_name [get_property top [get_filesets sources_1]]
    # ExplorePostRoutePhysOpt writes a legal optimized checkpoint after route.
    # Prefer it when present so sweep selection and final reports describe the
    # implementation that is actually used to produce the bitstream.
    set candidates [list \
        [file join $run_dir "${top_name}_postroute_physopt.dcp"] \
        [file join $run_dir "${top_name}_routed.dcp"]]
    if {$run_name eq "impl_1" && $checkpoint_dir ne ""} {
        lappend candidates [file join $checkpoint_dir "impl_1_route.dcp"]
    }

    foreach dcp $candidates {
        if {[file exists $dcp]} {
            puts "Opening $run_name routed checkpoint: $dcp"
            open_checkpoint $dcp
            return
        }
    }

    if {![catch {open_run $run_obj -name $run_name} msg]} {
        return
    }

    error "could not open $run_name ($msg) and no routed checkpoint found in: $candidates"
}

proc improve_post_route_timing {checkpoint_dir target_wns max_attempts} {
    set worst [get_timing_paths -quiet -setup -max_paths 1 -nworst 1]
    if {[llength $worst] == 0} {
        error "post-route design has no setup timing path"
    }

    set initial_wns [get_property SLACK [lindex $worst 0]]
    puts "Post-route timing before iterative physopt: WNS=$initial_wns ns"
    if {double($initial_wns) > double($target_wns)} {
        return $initial_wns
    }

    set source_dcp [file join $checkpoint_dir pre_iter_physopt_route.dcp]
    set best_dcp [file join $checkpoint_dir best_iter_physopt_route.dcp]
    write_checkpoint -force $source_dcp
    set best_wns $initial_wns
    file copy -force $source_dcp $best_dcp
    close_design

    for {set attempt 0} {$attempt < $max_attempts} {incr attempt} {
        open_checkpoint $source_dcp
        puts "Post-route iterative physopt attempt [expr {$attempt + 1}]/$max_attempts"
        phys_opt_design -directive AggressiveExplore
        set worst [get_timing_paths -quiet -setup -max_paths 1 -nworst 1]
        if {[llength $worst] == 0} {
            close_design
            error "iterative physopt produced no setup timing path"
        }
        set wns [get_property SLACK [lindex $worst 0]]
        puts "Post-route iterative physopt attempt [expr {$attempt + 1}] WNS=$wns ns"
        if {double($wns) > double($best_wns)} {
            set best_wns $wns
            write_checkpoint -force $best_dcp
        }
        close_design
        if {double($best_wns) > double($target_wns)} {
            break
        }
    }

    open_checkpoint $best_dcp
    if {double($best_wns) <= double($target_wns)} {
        error "post-route WNS $best_wns ns does not meet strict target > $target_wns ns"
    }
    puts "Post-route iterative physopt accepted: WNS=$best_wns ns"
    return $best_wns
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
set impl_runs [arg_value "-impl_runs" "1"]
set impl_mode [arg_value "-impl_mode" "sweep"]
set threads_per_run [arg_value "-threads_per_run" $jobs]
set run_to [arg_value "-run_to" "route"]
set sync_sources [arg_value "-sync_sources" "1"]
set force_runs [arg_value "-force" "1"]
set pll_freq_mhz [arg_value "-pll_freq_mhz" "150"]
set board_xdc [arg_value "-board_xdc" ""]
set enable_ila [arg_value "-enable_ila" "0"]
set irom_coe [file normalize [arg_value "-irom_coe" [file join $repo_root "FPGA/coe/irom_M3.coe"]]]
set dram_coe [file normalize [arg_value "-dram_coe" [file join $repo_root "FPGA/coe/dram_M.coe"]]]
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
puts "Implementation mode: $impl_mode, runs: $impl_runs"
puts "Run target: $run_to"
open_project $xpr

set max_threads [clamp_int $threads_per_run 1 32]
if {$max_threads != $threads_per_run} {
    puts "Vivado general.maxThreads is limited to $max_threads; launch_runs still uses -jobs $jobs"
}
puts "Vivado threads per process: $max_threads"
safe_param general.maxThreads $max_threads
catch {set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]}

remove_missing_sources
configure_board_constraints $board_xdc

if {$sync_sources} {
    remove_hw_ip_sources
    puts "Sourcing generated sources: $sources_tcl"
    source $sources_tcl
}

set_property top jyd_fpga [get_filesets sources_1]
configure_memory_coe IROM $irom_coe
configure_memory_coe DRAM $dram_coe
validate_clocking_frequency $pll_freq_mhz
configure_board_ila $enable_ila
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

if {$run_to eq "reports"} {
    set report_runs [discover_routed_implementation_runs]
    if {[llength $report_runs] == 0} {
        error "no implementation run has a routed checkpoint"
    }
    puts "Routed implementation runs available for reports: $report_runs"
    set report_impl_run [select_best_implementation $report_runs $report_dir $checkpoint_dir]
    open_impl_design $report_impl_run $checkpoint_dir
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
    write_checkpoint -force [file join $checkpoint_dir best_impl_route.dcp]

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
set synth_status [get_property STATUS [get_runs synth_1]]
if {!$force_runs && [regexp -nocase {complete} $synth_status]} {
    puts "Reusing completed synth_1: $synth_status"
} else {
    launch_runs synth_1 -jobs $jobs
    wait_on_run synth_1
}
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

set implementation_runs [prepare_implementation_runs $impl_runs $impl_mode]
if {$force_runs} {
    foreach run_name $implementation_runs {
        puts "Resetting $run_name"
        reset_run $run_name
    }
}

set pending_implementation_runs [list]
foreach run_name $implementation_runs {
    set status [get_property STATUS [get_runs $run_name]]
    if {!$force_runs && [regexp -nocase {complete} $status]} {
        puts "Reusing completed $run_name: $status"
    } else {
        lappend pending_implementation_runs $run_name
    }
}
if {$run_to ne "bitstream" && $run_to ne "route" && $run_to ne "impl"} {
    error "unknown -run_to value: $run_to"
}
if {[llength $pending_implementation_runs] > 0} {
    if {$run_to eq "bitstream"} {
        launch_runs $pending_implementation_runs -to_step write_bitstream -jobs $jobs
    } else {
        launch_runs $pending_implementation_runs -to_step route_design -jobs $jobs
    }
}
foreach run_name $implementation_runs {
    if {[lsearch -exact $pending_implementation_runs $run_name] >= 0} {
        wait_on_run $run_name
    }
    set status [get_property STATUS [get_runs $run_name]]
    puts "$run_name status: $status"
    if {[regexp -nocase {fail|error} $status] &&
        ![regexp -nocase {complete.*failed timing} $status]} {
        puts "warning: implementation sweep run $run_name failed; remaining runs will still be evaluated"
    } elseif {[regexp -nocase {failed timing} $status]} {
        puts "warning: implementation sweep run $run_name completed with timing violations"
    }
}
set best_impl_run [select_best_implementation $implementation_runs $report_dir $checkpoint_dir]

set impl_run_dir ""
set top_name [get_property top [get_filesets sources_1]]
set impl_run_obj [get_runs -quiet $best_impl_run]
if {[llength $impl_run_obj] > 0} {
    set impl_run_dir [get_property DIRECTORY $impl_run_obj]
}

open_impl_design $best_impl_run $checkpoint_dir
set final_wns [improve_post_route_timing $checkpoint_dir -0.100 4]
set best_fp [open [file join $report_dir best_implementation.txt] a]
puts $best_fp "iterative_physopt_wns_ns=$final_wns"
close $best_fp
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
write_checkpoint -force [file join $checkpoint_dir best_impl_route.dcp]
if {$enable_ila} {
    write_debug_probes -force [file join $impl_run_dir "${top_name}.ltx"]
}
if {$run_to eq "bitstream"} {
    write_bitstream -force [file join $impl_run_dir "${top_name}.bit"]
}
archive_run_artifacts $best_impl_run $artifact_dir $pll_freq_mhz $run_to $report_dir $checkpoint_dir $impl_run_dir $top_name

puts "Reports written to $report_dir"
close_project
