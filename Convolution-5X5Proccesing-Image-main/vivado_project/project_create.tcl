# Vivado project skeleton for convolution_fpga
# Usage example:
# vivado -mode batch -source vivado_project/project_create.tcl

set proj_name convolution_fpga
set proj_dir [file normalize "./vivado_project/builds/${proj_name}"]
set top_name top_convolution
set part_name xc7z020clg400-1

file mkdir $proj_dir
create_project $proj_name $proj_dir -part $part_name -force

set src_list [list \
    [file normalize "./src/top_convolution.sv"] \
    [file normalize "./src/line_buffer_4.sv"] \
    [file normalize "./src/kernel_loader.sv"] \
    [file normalize "./src/mac_array_25x3.sv"] \
    [file normalize "./src/axi_stream_conv_wrapper.sv"] \
    [file normalize "./src/axi_lite_kernel_ctrl.sv"]
]

foreach f $src_list {
    add_files -norecurse $f
}

set_property top $top_name [current_fileset]

set xdc_file [file normalize "./vivado_project/constraints.xdc"]
if {[file exists $xdc_file]} {
    add_files -fileset constrs_1 -norecurse $xdc_file
}

update_compile_order -fileset sources_1
close_project
puts "Project created at: $proj_dir"
