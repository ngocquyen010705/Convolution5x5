# Batch synthesis/implementation script
# Usage example:
# vivado -mode batch -source vivado_project/run_synth.tcl

set proj_name convolution_fpga
set proj_xpr [file normalize "./vivado_project/builds/${proj_name}/${proj_name}.xpr"]
set rpt_dir [file normalize "./vivado_project/reports"]

file mkdir $rpt_dir

if {![file exists $proj_xpr]} {
    puts "Project not found, creating project first..."
    source [file normalize "./vivado_project/project_create.tcl"]
}

open_project $proj_xpr
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

open_run synth_1
report_timing_summary -file [file normalize "${rpt_dir}/timing_post_synth.rpt"]
report_utilization -file [file normalize "${rpt_dir}/util_post_synth.rpt"]

reset_run impl_1
# O3: favor timing closure with stronger implementation directives.
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE ExploreWithRemap [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1

open_run impl_1
report_timing_summary -file [file normalize "${rpt_dir}/timing_post_route.rpt"]
report_utilization -file [file normalize "${rpt_dir}/util_post_route.rpt"]

set activity_file ""
set activity_strip_path ""
if {[info exists ::env(POWER_ACTIVITY_FILE)]} {
    set activity_file [file normalize $::env(POWER_ACTIVITY_FILE)]
}
if {[info exists ::env(POWER_ACTIVITY_STRIP_PATH)]} {
    set activity_strip_path $::env(POWER_ACTIVITY_STRIP_PATH)
}

if {$activity_file ne "" && [file exists $activity_file]} {
    puts "Applying activity data from $activity_file"
    if {[string match "*.saif" [string tolower $activity_file]]} {
        set strip_candidates [list]
        if {$activity_strip_path ne ""} {
            lappend strip_candidates $activity_strip_path
        }
        lappend strip_candidates "tb_activity_saif/dut" "/tb_activity_saif/dut" "tb_convolution/dut" "/tb_convolution/dut" ""

        set saif_ok 0
        foreach sp $strip_candidates {
            if {$sp eq ""} {
                set rc [catch {read_saif $activity_file} saif_msg]
                puts "SAIF import try: no strip_path => $saif_msg"
            } else {
                set rc [catch {read_saif $activity_file -strip_path $sp} saif_msg]
                puts "SAIF import try: strip_path=$sp => $saif_msg"
            }
            if {$rc == 0} {
                set saif_ok 1
                break
            }
        }

        if {!$saif_ok} {
            puts "SAIF import failed for all strip_path candidates"
        }
    } elseif {[string match "*.vcd" [string tolower $activity_file]]} {
        if {$activity_strip_path ne ""} {
            catch {read_vcd -file $activity_file -strip_path $activity_strip_path} vcd_msg
        } else {
            catch {read_vcd -file $activity_file} vcd_msg
        }
        puts "VCD import status: $vcd_msg"
    } else {
        puts "Unsupported activity extension for $activity_file (expected .vcd or .saif)"
    }
} else {
    puts "No activity file provided; power uses default toggle assumptions"
}

report_power -file [file normalize "${rpt_dir}/power_post_route.rpt"]

puts "Synthesis/implementation done. Reports in $rpt_dir"
