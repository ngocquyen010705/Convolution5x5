# XSIM batch script to collect switching activity as SAIF.
# Usage from tb/: xsim tb_convolution_xsim -tclbatch xsim_saif.tcl -tclargs ../sim/activity.saif

set saif_out "../sim/activity.saif"
set saif_scope "/tb_activity_saif/dut/*"
if {[info exists ::env(SAIF_OUT)]} {
    set saif_out $::env(SAIF_OUT)
}
if {[info exists ::env(SAIF_SCOPE)]} {
    set saif_scope $::env(SAIF_SCOPE)
}
set saif_out [file normalize $saif_out]

puts "SAIF output: $saif_out"
puts "SAIF scope: $saif_scope"

# Scope at DUT level to keep activity mapping stable for implementation netlist.
open_saif $saif_out
log_saif [get_objects -r $saif_scope]
run all
close_saif
quit
