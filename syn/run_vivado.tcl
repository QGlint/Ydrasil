# Batch Vivado synthesis/implementation driver for the Ydrasil FPGA project.

proc usage {} {
    puts "usage: vivado -mode batch -source syn/run_vivado.tcl -tclargs ?options?"
    puts "  -xpr <path>             Vivado project, default FPGA/Ydrasil_FPGA.xpr"
    puts "  -part <name>            FPGA part used when creating a new project"
    puts "  -staging_dir <path>     pre-project sources copied after create_project"
    puts "  -sources_tcl <path>     generated source sync Tcl"
    puts "  -top <module>           synthesis top, default ydrasil_soc"
    puts "  -report_dir <path>      report output directory"
    puts "  -jobs <n>               Vivado launch job count"
    puts "  -threads_per_run <n>    max threads used by each Vivado process"
    puts "  -impl_runs <n>          parallel implementation run count, default 1"
    puts "  -impl_mode <sweep|extreme>  implementation tuning mode, default sweep"
    puts "  -impl_way <0|1|2|3|4|full> implementation strategy selector, default 0"
    puts "  -synth_strategy <name>  Vivado synthesis strategy, default Flow_PerfOptimized_high"
    puts "  -sweep_post_route_physopt <0|1>  enable sweep post-route phys_opt step, default 0"
    puts "  -run_to <synth|route|bitstream|reports|sync_only>"
    puts "  -sync_sources <0|1>     remove old hw/ip sources and add generated list"
    puts "  -reuse_synth <0|1>      reuse an unchanged staged synth_1 run, default 0"
    puts "  -reset_impl <0|1>       reset implementation runs without resetting synth_1, default 0"
    puts "  -report_synth <0|1>     generate and open post-synth reports, default 1"
    puts "  -force <0|1>            reset runs before launching"
    puts "  -pll_freq_mhz <mhz>     CPU frequency selected by the RTL MMCM define"
    puts "  -board_xdc <path>       overlay board-specific constraints after platform constraints"
    puts "  -replace_constraints <0|1> disable project XDC files before adding board_xdc"
    puts "  -enable_ila <0|1>       create ila_board for the conditional board probes"
    puts "  -itcm_mem <path>        XPM ITCM initialization .mem file"
    puts "  -dtcm_mem <path>        XPM DTCM initialization .mem file"
    puts "  -legacy_ip <0|1>        preserve generated IP for the legacy jyd_fpga top"
    puts "  -artifact_dir <path>    copied bitstream/artifact output directory"
    puts "  -timing_summary_max_paths <n>  timing summary path limit, default 5000"
    puts "  -timing_path_max_paths <n>     violating report_timing path limit, default 5000"
    puts "  -timing_nworst <n>             report_timing nworst per endpoint/group, default 1"
    puts "  -full_reports <0|1>            enable extended diagnostic reports, default 0"
    puts "  -post_route_physopt <0|1>      enable one extra post-route physopt pass, default 0"
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

proc format_elapsed_ms {elapsed_ms} {
    set total_ms [expr {wide($elapsed_ms)}]
    set hours [expr {$total_ms / 3600000}]
    set minutes [expr {($total_ms / 60000) % 60}]
    set seconds [expr {($total_ms / 1000) % 60}]
    set milliseconds [expr {$total_ms % 1000}]
    return [format "%02d:%02d:%02d.%03d" $hours $minutes $seconds $milliseconds]
}

proc print_flow_elapsed {started_ms} {
    set elapsed_ms [expr {[clock milliseconds] - $started_ms}]
    puts "Vivado flow elapsed: [format_elapsed_ms $elapsed_ms]"
}

proc get_run_elapsed {run_name} {
    set elapsed ""
    catch {set elapsed [get_property STATS.ELAPSED [get_runs $run_name]]}
    if {$elapsed eq ""} {
        return "unavailable"
    }
    return $elapsed
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

proc configure_sweep_implementation {run_name strategy sweep_post_route_physopt} {
    set run [get_runs $run_name]
    set_property strategy $strategy $run
    set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $run
    if {!$sweep_post_route_physopt} {
        # Vivado 2024.2 can segfault in libxv_power.so while executing the
        # Performance_ExplorePostRoutePhysOpt post-route path optimizer.
        set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED false $run
    }
}

proc prepare_implementation_runs {count mode sweep_post_route_physopt way} {
    if {$mode eq "extreme"} {
        configure_performance_implementation impl_1
        puts "Selected implementation way: 4 (extreme)"
        return [list impl_1]
    }
    if {$mode ne "sweep"} {
        error "unknown -impl_mode value: $mode"
    }

    set strategies [list \
        Performance_ExplorePostRoutePhysOpt \
        Performance_Explore \
        Performance_NetDelay_high \
        Performance_ExtraTimingOpt \
        Performance_Retiming \
        Performance_ExploreWithRemap ]
    # Keep way 3 available for an explicit single run, but exclude it from
    # the routine full sweep.
    set candidate_strategies [list \
        Performance_Retiming \
        Performance_RefinePlacement]

    if {$way eq "full"} {
        set count [clamp_int $count 1 3]
        set selected_strategies [lrange $strategies 0 [expr {$count - 1}]]
    } elseif {[string is integer -strict $way] && $way >= 0 && $way < 4} {
        set selected_strategies [list [lindex $strategies $way]]
    } else {
        error "unknown -impl_way value for sweep mode: $way"
    }

    set unselected_strategies [list]
    foreach strategy $strategies {
        if {[lsearch -exact $selected_strategies $strategy] < 0} {
            lappend unselected_strategies $strategy
        }
    }
    puts "Selected implementation way: $way"
    puts "Selected implementation strategies: $selected_strategies"
    puts "Unselected implementation strategies: $unselected_strategies"
    puts "Candidate implementation strategies (disabled): $candidate_strategies"
    set runs [list]
    set idx 0
    foreach strategy $selected_strategies {
        set run_name [expr {$idx == 0 ? "impl_1" : "impl_sweep_$idx"}]
        if {$idx > 0 && [llength [get_runs -quiet $run_name]] == 0} {
            create_run $run_name -parent_run synth_1 -flow {Vivado Implementation 2024} \
                -strategy $strategy
        }
        configure_sweep_implementation $run_name $strategy $sweep_post_route_physopt
        lappend runs $run_name
        puts "Implementation sweep: $run_name strategy=$strategy"
        incr idx
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
            catch {set wns [get_property STATS.WNS $run]}
            if {![string is double -strict $wns]} {
                set wns ""
                if {[catch {open_impl_design $run_name $checkpoint_dir} open_msg]} {
                    puts "warning: could not evaluate implementation run $run_name: $open_msg"
                } else {
                    set worst [get_timing_paths -quiet -delay_type max -max_paths 1 -nworst 1]
                    if {[llength $worst] > 0} {
                        set wns [get_property SLACK [lindex $worst 0]]
                    }
                    close_design
                }
            }
            if {$wns ne "" && ($best_run eq "" || double($wns) > double($best_wns))} {
                set best_run $run_name
                set best_wns $wns
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
        if {[regexp {/(hw/ip)/.*\.(sv|v|svh|vh)$} $nf]} {
            lappend stale $f
        }
    }
    if {[llength $stale] > 0} {
        puts "Removing [llength $stale] existing hw/ip RTL/header files from sources_1"
        remove_files -fileset $fs $stale
    }
}

proc remove_legacy_generated_ips {} {
    foreach ip_name {IROM DRAM BRAM pll} {
        foreach ip_obj [get_ips -quiet $ip_name] {
            set ip_file [get_property IP_FILE $ip_obj]
            if {$ip_file ne ""} {
                puts "Removing unused generated IP from the new SoC project: $ip_name"
                if {[catch {remove_files $ip_file} msg]} {
                    puts "warning: could not remove $ip_name: $msg"
                }
            }
        }
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

proc configure_board_constraints {board_xdc replace_constraints} {
    if {$board_xdc eq ""} {
        puts "Using platform constraints from the project"
        return
    }
    set board_xdc [file normalize $board_xdc]
    if {![file exists $board_xdc]} {
        error "board constraint file not found: $board_xdc"
    }

    set fs [get_filesets constrs_1]
    if {$replace_constraints} {
        puts "Disabling project constraints before applying board constraints"
        foreach old_xdc [get_files -of_objects $fs -filter {FILE_TYPE == XDC}] {
            catch {set_property USED_IN_SYNTHESIS false $old_xdc}
            catch {set_property USED_IN_IMPLEMENTATION false $old_xdc}
        }
    }
    puts "Adding board constraints: $board_xdc"
    add_files -norecurse -fileset $fs $board_xdc
    set_property USED_IN_SYNTHESIS true [get_files -of_objects $fs $board_xdc]
    set_property USED_IN_IMPLEMENTATION true [get_files -of_objects $fs $board_xdc]
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
    set configured_property [get_property CONFIG.Coe_File $ip]
    if {[file pathtype $configured_property] eq "relative"} {
        set configured_coe [file normalize [file join \
            [file dirname [get_property IP_FILE $ip]] $configured_property]]
    } else {
        set configured_coe [file normalize $configured_property]
    }
    if {$configured_coe ne $coe_file} {
        error "$ip_name COE configuration mismatch: requested $coe_file, got $configured_coe"
    }
}

proc assert_run_ok {run_name} {
    set status [get_property STATUS [get_runs $run_name]]
    puts "$run_name status: $status"
    if {[regexp -nocase {fail|error} $status]} {
        error "$run_name failed: $status"
    }
}

proc validate_io_constraints {} {
    set missing_package_pin [list]
    set missing_iostandard [list]
    foreach port [get_ports -quiet *] {
        set port_name [get_property NAME $port]
        if {[get_property PACKAGE_PIN $port] eq ""} {
            lappend missing_package_pin $port_name
        }
        set iostandard [get_property IOSTANDARD $port]
        if {$iostandard eq "" || $iostandard eq "DEFAULT"} {
            lappend missing_iostandard $port_name
        }
    }
    if {[llength $missing_package_pin] > 0 ||
        [llength $missing_iostandard] > 0} {
        error "incomplete board constraints: missing PACKAGE_PIN={$missing_package_pin}; missing IOSTANDARD={$missing_iostandard}"
    }
    puts "Validated PACKAGE_PIN and IOSTANDARD on [llength [get_ports -quiet *]] top-level ports"
}

proc report_and_validate_drc {report_file} {
    report_drc -file $report_file
    set error_violations [list]
    foreach violation [get_drc_violations -quiet] {
        set violation_name [get_property NAME $violation]
        set rule_name [lindex [split $violation_name "#"] 0]
        set rule [get_drc_checks -quiet $rule_name]
        if {[llength $rule] > 0 && [get_property SEVERITY $rule] eq "Error"} {
            lappend error_violations $violation_name
        }
    }
    if {[llength $error_violations] > 0} {
        error "post-synthesis DRC errors: {$error_violations}; see $report_file"
    }
    puts "Post-synthesis DRC contains no Error-severity violations"
}

proc ensure_dir {dir_name} {
    file mkdir $dir_name
    return [file normalize $dir_name]
}

proc copy_tree {source_dir destination_dir} {
    if {![file isdirectory $source_dir]} {
        error "staged directory not found: $source_dir"
    }
    file mkdir $destination_dir
    foreach source [glob -nocomplain -directory $source_dir *] {
        set destination [file join $destination_dir [file tail $source]]
        if {[file isdirectory $source]} {
            copy_tree $source $destination
        } else {
            file copy -force $source $destination
        }
    }
}

proc report_if_possible {description command} {
    puts "Writing $description"
    if {[catch {uplevel 1 $command} msg]} {
        puts "warning: failed to write $description: $msg"
    }
}

proc clean_skipped_reports {report_dir} {
    global full_reports
    set stale [list post_route_timing_paths.rpt]
    if {!$full_reports} {
        lappend stale \
            post_route_clock_interaction.rpt \
            post_route_check_timing.rpt \
            post_route_drc.rpt \
            post_route_methodology.rpt \
            post_route_design_analysis.rpt \
            post_route_qor_suggestions.rpt
    }
    foreach name $stale {
        file delete -force [file join $report_dir $name]
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
    global full_reports timing_summary_max_paths timing_path_max_paths timing_nworst

    set target_period [expr {1000.0 / double($freq_mhz)}]
    set tag [freq_file_tag $freq_mhz]
    file delete -force [file join $report_dir cpu${tag}_timing_paths.rpt]
    if {!$full_reports} {
        file delete -force [file join $report_dir cpu${tag}_timing_summary.rpt]
    }
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

    if {$full_reports} {
        puts "Writing $freq_mhz MHz timing summary"
        if {[catch {
            report_timing_summary -delay_type max -max_paths $timing_summary_max_paths -report_unconstrained \
                -file [file join $report_dir cpu${tag}_timing_summary.rpt]
        } msg]} {
            puts "warning: failed to write $freq_mhz MHz timing summary: $msg"
        }
    }
    puts "Writing $freq_mhz MHz violating timing paths"
    if {[catch {
        report_timing -delay_type max -from $cpu_clocks -to $cpu_clocks -sort_by slack \
            -slack_lesser_than 0.000 -max_paths $timing_path_max_paths -nworst $timing_nworst \
            -unique_pins -input_pins -file [file join $report_dir cpu${tag}_timing_violations.rpt]
    } msg]} {
        puts "warning: failed to write $freq_mhz MHz violating timing paths: $msg"
    }
}

proc validate_clocking_frequency {freq_mhz legacy_ip} {
    set freq_mhz [string trim $freq_mhz]
    if {![regexp {^[0-9]+([.][0-9]+)?$} $freq_mhz] || double($freq_mhz) <= 0.0} {
        error "invalid -pll_freq_mhz value: $freq_mhz"
    }

    if {!$legacy_ip || double($freq_mhz) != 200.0} {
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
    global board_xdc dtcm_mem enable_ila itcm_mem
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

    set project_dir [get_property DIRECTORY [current_project]]
    set patterns [list \
        [file join $run_dir "${top_name}.bit"] \
        [file join $run_dir "${top_name}*.bit"] \
        [file join $run_dir "${top_name}*.mmi"] \
        [file join $run_dir "*.mmi"] \
        [file join $project_dir "*.mmi"] \
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
    puts $fp "itcm_mem=$itcm_mem"
    puts $fp "dtcm_mem=$dtcm_mem"
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
    if {$max_attempts <= 0 || double($initial_wns) >= double($target_wns)} {
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
        if {double($best_wns) >= double($target_wns)} {
            break
        }
    }

    open_checkpoint $best_dcp
    if {double($best_wns) < double($target_wns)} {
        puts "warning: post-route WNS $best_wns ns does not meet target >= $target_wns ns; continuing with reports and artifacts"
    } else {
        puts "Post-route iterative physopt accepted: WNS=$best_wns ns"
    }
    return $best_wns
}

if {[lsearch -exact $argv "-help"] >= 0 || [lsearch -exact $argv "--help"] >= 0} {
    usage
    exit 0
}

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]

set xpr [file normalize [arg_value "-xpr" [file join $repo_root "FPGA/Ydrasil_FPGA.xpr"]]]
set part [arg_value "-part" "xc7k325tffg900-2"]
set staging_dir [arg_value "-staging_dir" ""]
set sources_tcl [file normalize [arg_value "-sources_tcl" [file join $repo_root "build/syn/vivado_sources.tcl"]]]
set requested_top [arg_value "-top" "ydrasil_soc"]
set report_dir [ensure_dir [arg_value "-report_dir" [file join $repo_root "build/syn/reports"]]]
set checkpoint_dir [ensure_dir [arg_value "-checkpoint_dir" [file join $repo_root "build/syn/checkpoints"]]]
set artifact_dir [ensure_dir [arg_value "-artifact_dir" [file join $repo_root "build/syn/artifacts"]]]
set jobs [arg_value "-jobs" "16"]
set impl_runs [arg_value "-impl_runs" "1"]
set impl_mode [arg_value "-impl_mode" "sweep"]
set impl_way [arg_value "-impl_way" "0"]
set synth_strategy [arg_value "-synth_strategy" "Flow_PerfOptimized_high"]
set sweep_post_route_physopt [clamp_int [arg_value "-sweep_post_route_physopt" "0"] 0 1]
set threads_per_run [arg_value "-threads_per_run" $jobs]
set run_to [arg_value "-run_to" "route"]
set sync_sources [arg_value "-sync_sources" "1"]
set reuse_synth [clamp_int [arg_value "-reuse_synth" "0"] 0 1]
set reset_impl [clamp_int [arg_value "-reset_impl" "0"] 0 1]
set report_synth [clamp_int [arg_value "-report_synth" "1"] 0 1]
set force_runs [arg_value "-force" "1"]
set pll_freq_mhz [arg_value "-pll_freq_mhz" "150"]
set board_xdc [arg_value "-board_xdc" ""]
set replace_constraints [clamp_int [arg_value "-replace_constraints" "0"] 0 1]
set enable_ila [arg_value "-enable_ila" "0"]
set itcm_mem [file normalize [arg_value "-itcm_mem" [file join $repo_root "build/syn/memory/itcm.mem"]]]
set dtcm_mem [file normalize [arg_value "-dtcm_mem" [file join $repo_root "build/syn/memory/dtcm.mem"]]]
set legacy_ip [clamp_int [arg_value "-legacy_ip" "0"] 0 1]
set timing_summary_max_paths [arg_value "-timing_summary_max_paths" "5000"]
set timing_path_max_paths [arg_value "-timing_path_max_paths" "5000"]
set timing_nworst [arg_value "-timing_nworst" "1"]
set full_reports [clamp_int [arg_value "-full_reports" "0"] 0 1]
set post_route_physopt [clamp_int [arg_value "-post_route_physopt" "0"] 0 1]

if {$impl_way ne "full" &&
    (![string is integer -strict $impl_way] || $impl_way < 0 || $impl_way > 4)} {
    error "unknown -impl_way value: $impl_way; expected 0, 1, 2, 3, 4, or full"
}
if {$impl_mode eq "sweep" && $impl_way eq "4"} {
    error "-impl_way 4 requires -impl_mode extreme"
}

if {$sync_sources && ![file exists $sources_tcl]} {
    error "generated sources Tcl not found: $sources_tcl"
}
if {$reuse_synth && $sync_sources} {
    error "-reuse_synth requires -sync_sources 0 to preserve synth_1"
}
if {$reuse_synth && $force_runs} {
    error "-reuse_synth requires -force 0 to preserve synth_1"
}
if {$reuse_synth && $run_to ne "route" && $run_to ne "bitstream" &&
    $run_to ne "impl" && $run_to ne "reports"} {
    error "-reuse_synth is only valid with -run_to route, bitstream, impl, or reports"
}

puts "Vivado project: $xpr"
puts "Vivado jobs: $jobs"
puts "Implementation mode: $impl_mode, runs: $impl_runs, way: $impl_way"
puts "Synthesis strategy: $synth_strategy"
puts "Sweep post-route phys_opt: $sweep_post_route_physopt"
puts "Run target: $run_to"
puts "Synthesis top: $requested_top"
puts "Reuse completed synthesis: $reuse_synth"
set flow_started_ms [clock milliseconds]
set created_project 0
if {[file exists $xpr]} {
    puts "Opening existing project"
    open_project $xpr
} else {
    set project_dir [file dirname $xpr]
    set project_name [file rootname [file tail $xpr]]
    file mkdir $project_dir
    puts "Creating fresh project: name=$project_name part=$part directory=$project_dir"
    create_project $project_name $project_dir -part $part -force
    set created_project 1
}
if {$created_project} {
    if {$staging_dir eq ""} {
        error "a fresh project requires -staging_dir"
    }
    set staging_dir [file normalize $staging_dir]
    set project_dir [file normalize [get_property DIRECTORY [current_project]]]
    set project_srcs [file join $project_dir Ydrasil_FPGA.srcs]
    puts "Materializing staged sources inside the fresh project"
    copy_tree [file join $staging_dir sources_1] [file join $project_srcs sources_1]
    copy_tree [file join $staging_dir constrs_1] [file join $project_srcs constrs_1]
}
if {!$legacy_ip && !$reuse_synth && (![file exists $itcm_mem] || ![file exists $dtcm_mem])} {
    error "XPM initialization files are missing: ITCM=$itcm_mem DTCM=$dtcm_mem"
}

set max_threads [clamp_int $threads_per_run 1 32]
if {$max_threads != $threads_per_run} {
    puts "Vivado general.maxThreads is limited to $max_threads; launch_runs still uses -jobs $jobs"
}
puts "Vivado threads per process: $max_threads"
safe_param general.maxThreads $max_threads
if {!$reuse_synth} {
    # A staged project may retain an INCREMENTAL_CHECKPOINT property from a
    # previous host/build tree even when the imported DCP has been removed.
    # This build is an architectural timing measurement, so clear it before a
    # fresh synthesis setup.  Do not touch it when a completed synth_1 is
    # intentionally being reused by a separate implementation process.
    foreach run_obj [get_runs -quiet] {
        catch {set_property INCREMENTAL_CHECKPOINT "" $run_obj}
    }

    catch {set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]}
    remove_missing_sources
    configure_board_constraints $board_xdc $replace_constraints

    if {$sync_sources} {
        remove_hw_ip_sources
        puts "Sourcing generated sources: $sources_tcl"
        source $sources_tcl
    }

    if {$created_project} {
        file delete -force $staging_dir
    }

    set_property top $requested_top [get_filesets sources_1]
    if {!$legacy_ip} {
        remove_legacy_generated_ips
    }
    validate_clocking_frequency $pll_freq_mhz $legacy_ip
    configure_board_ila $enable_ila
    update_compile_order -fileset sources_1

    if {$run_to eq "sync_only"} {
        puts "Source synchronization complete."
        close_project
        print_flow_elapsed $flow_started_ms
        exit 0
    }

    set flow_ips [list]
    if {$legacy_ip} {
        set flow_ips [get_ips -quiet]
    } elseif {$enable_ila} {
        set flow_ips [get_ips -quiet ila_board]
    }
    if {$run_to ne "reports" && [llength $flow_ips] > 0} {
        set flow_ip_names [list]
        foreach flow_ip $flow_ips {
            lappend flow_ip_names [get_property NAME $flow_ip]
        }
        puts "Refreshing generated IP output products: $flow_ip_names"
        generate_target all $flow_ips
    } elseif {!$legacy_ip} {
        puts "New SoC uses RTL/XPM sources; no generated IP output products are required"
    }
} else {
    puts "Reusing staged synth_1 without modifying sources, IP products, or clocking"
}

if {$run_to eq "reports"} {
    clean_skipped_reports $report_dir
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
        "report_timing -delay_type max -sort_by slack -slack_lesser_than 0.000 -max_paths $timing_path_max_paths -nworst $timing_nworst -unique_pins -input_pins -file [file join $report_dir post_route_timing_violations.rpt]"
    report_if_possible "post-route clocks" \
        "report_clocks -file [file join $report_dir post_route_clocks.rpt]"
    report_cpu_freq_timing $report_dir $pll_freq_mhz
    report_if_possible "post-route utilization" \
        "report_utilization -hierarchical -file [file join $report_dir post_route_utilization_hier.rpt]"
    report_if_possible "route status" \
        "report_route_status -file [file join $report_dir post_route_status.rpt]"
    if {$full_reports} {
        report_if_possible "post-route clock interaction" \
            "report_clock_interaction -delay_type max -file [file join $report_dir post_route_clock_interaction.rpt]"
        report_if_possible "post-route check timing" \
            "check_timing -verbose -file [file join $report_dir post_route_check_timing.rpt]"
        report_if_possible "post-route DRC" \
            "report_drc -file [file join $report_dir post_route_drc.rpt]"
        report_if_possible "post-route methodology" \
            "report_methodology -file [file join $report_dir post_route_methodology.rpt]"
        report_if_possible "post-route design analysis" \
            "report_design_analysis -timing -logic_level_distribution -file [file join $report_dir post_route_design_analysis.rpt]"
        report_if_possible "QoR suggestions" \
            "report_qor_suggestions -file [file join $report_dir post_route_qor_suggestions.rpt]"
    }
    write_checkpoint -force [file join $checkpoint_dir best_impl_route.dcp]

    puts "Reports written to $report_dir"
    close_project
    print_flow_elapsed $flow_started_ms
    exit 0
}

if {!$reuse_synth} {
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
    set synth_run [get_runs synth_1]
    # Reset first because an XPR may retain per-step arguments from an earlier
    # strategy. The default is the strongest supported 2024.2 timing-oriented
    # preset; exposing it lets a low-memory trial retain aggressive
    # implementation directives without retaining a previous synth strategy.
    set_property strategy {Vivado Synthesis Defaults} $synth_run
    if {[catch {set_property strategy $synth_strategy $synth_run} synth_strategy_msg]} {
        error "could not apply synthesis strategy '$synth_strategy': $synth_strategy_msg"
    }
    set synth_status [get_property STATUS [get_runs synth_1]]
    if {!$force_runs && [regexp -nocase {complete} $synth_status]} {
        puts "Reusing completed synth_1: $synth_status"
    } else {
        launch_runs synth_1 -jobs $jobs
        wait_on_run synth_1
    }
} else {
    set synth_status [get_property STATUS [get_runs synth_1]]
    if {![regexp -nocase {complete} $synth_status]} {
        error "requested synth_1 reuse, but status is '$synth_status'"
    }
    puts "Reusing completed synth_1: $synth_status"
}
assert_run_ok synth_1
puts "Synthesis result: synth_1 status=[get_property STATUS [get_runs synth_1]] elapsed=[get_run_elapsed synth_1]"

open_run synth_1 -name synth_1
validate_io_constraints
report_and_validate_drc [file join $report_dir synth_drc.rpt]
if {$report_synth} {
    report_if_possible "post-synthesis utilization" \
        "report_utilization -hierarchical -file [file join $report_dir synth_utilization_hier.rpt]"
    report_if_possible "post-synthesis timing summary" \
        "report_timing_summary -delay_type max -max_paths $timing_summary_max_paths -report_unconstrained -file [file join $report_dir synth_timing_summary.rpt]"
    report_if_possible "post-synthesis clocks" \
        "report_clocks -file [file join $report_dir synth_clocks.rpt]"
    report_cpu_freq_timing $report_dir $pll_freq_mhz
    report_if_possible "post-synthesis methodology" \
        "report_methodology -file [file join $report_dir synth_methodology.rpt]"
    write_checkpoint -force [file join $checkpoint_dir synth_1.dcp]
}
close_design

if {$run_to eq "synth"} {
    close_project
    print_flow_elapsed $flow_started_ms
    exit 0
}

set implementation_runs [prepare_implementation_runs \
    $impl_runs $impl_mode $sweep_post_route_physopt $impl_way]
if {$force_runs || $reset_impl} {
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
    puts "Launching implementation runs in parallel: $pending_implementation_runs"
    if {$run_to eq "bitstream"} {
        launch_runs $pending_implementation_runs -to_step write_bitstream -jobs $jobs
    } else {
        launch_runs $pending_implementation_runs -to_step route_design -jobs $jobs
    }
}
foreach run_name $implementation_runs {
    if {[lsearch -exact $pending_implementation_runs $run_name] >= 0} {
        if {[catch {wait_on_run $run_name} wait_msg]} {
            puts "INFO: implementation run $run_name terminated unsuccessfully; ignoring this candidate: $wait_msg"
        }
    }
    set status [get_property STATUS [get_runs $run_name]]
    puts "$run_name status: $status elapsed=[get_run_elapsed $run_name]"
    if {[regexp -nocase {fail|error} $status] &&
        ![regexp -nocase {complete.*failed timing} $status]} {
        puts "INFO: implementation sweep run $run_name failed; remaining runs will still be evaluated"
    } elseif {[regexp -nocase {failed timing} $status]} {
        puts "INFO: implementation sweep run $run_name completed with timing violations"
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
clean_skipped_reports $report_dir
set final_wns [improve_post_route_timing $checkpoint_dir -0.500 $post_route_physopt]
set best_fp [open [file join $report_dir best_implementation.txt] a]
puts $best_fp "final_wns_ns=$final_wns"
close $best_fp
report_if_possible "post-route timing summary" \
    "report_timing_summary -delay_type max -max_paths $timing_summary_max_paths -report_unconstrained -check_timing_verbose -file [file join $report_dir post_route_timing_summary.rpt]"
report_if_possible "post-route violating timing paths" \
    "report_timing -delay_type max -sort_by slack -slack_lesser_than 0.000 -max_paths $timing_path_max_paths -nworst $timing_nworst -unique_pins -input_pins -file [file join $report_dir post_route_timing_violations.rpt]"
report_if_possible "post-route clocks" \
    "report_clocks -file [file join $report_dir post_route_clocks.rpt]"
report_cpu_freq_timing $report_dir $pll_freq_mhz
report_if_possible "post-route utilization" \
    "report_utilization -hierarchical -file [file join $report_dir post_route_utilization_hier.rpt]"
report_if_possible "route status" \
    "report_route_status -file [file join $report_dir post_route_status.rpt]"
if {$full_reports} {
    report_if_possible "post-route clock interaction" \
        "report_clock_interaction -delay_type max -file [file join $report_dir post_route_clock_interaction.rpt]"
    report_if_possible "post-route check timing" \
        "check_timing -verbose -file [file join $report_dir post_route_check_timing.rpt]"
    report_if_possible "post-route DRC" \
        "report_drc -file [file join $report_dir post_route_drc.rpt]"
    report_if_possible "post-route methodology" \
        "report_methodology -file [file join $report_dir post_route_methodology.rpt]"
    report_if_possible "post-route design analysis" \
        "report_design_analysis -timing -logic_level_distribution -file [file join $report_dir post_route_design_analysis.rpt]"
    report_if_possible "QoR suggestions" \
        "report_qor_suggestions -file [file join $report_dir post_route_qor_suggestions.rpt]"
}
write_checkpoint -force [file join $checkpoint_dir best_impl_route.dcp]
if {$enable_ila} {
    write_debug_probes -force [file join $impl_run_dir "${top_name}.ltx"]
}
if {$run_to eq "bitstream" && $post_route_physopt} {
    write_bitstream -force [file join $impl_run_dir "${top_name}.bit"]
}
archive_run_artifacts $best_impl_run $artifact_dir $pll_freq_mhz $run_to $report_dir $checkpoint_dir $impl_run_dir $top_name

puts "Reports written to $report_dir"
close_project
print_flow_elapsed $flow_started_ms
