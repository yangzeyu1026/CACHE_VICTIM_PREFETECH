# CACHE_VICTIM_PREFETECH
This is the code that implement a write-back directly-mapped cache with victim buffer and hardware prefetch. These are synthesizable.
## Usage
This part tells how to use these code.
### Requirement
Vivado (>= 2021.2 is enough)
### Sources in Vivado
```
|-Design Sources
  |-Global Include
    |-ISA.svh
    |-sys_defs.svh
  |-pipeline.sv
    |-*_stage.sv
    |-regfile.sv
  |-mmu.sv
    |-Imem.sv
    |-Dmem.sv
    |-data_cache.sv
      |-victim_buffer.sv
      |-lru.sv
    |-prefetch.sv
      |-utility.sv (lru.sv)
|-Simulation Sources
  |-testbench.sv(must be set as top module)
  |-program.mem(will be talked about in details later)
```
### Parameter Adjustment
In file data_cache_final_version.sv line 116, you can change the victim buffer size. Now it only support size in powers of 2, I will fix that. In file data_cache_final_version.sv line 275, you can change the parameters of stream buffer, including `way` and `queue_size`.
### Generate Machine code
You need to install `riscv32-toolchain` and `elf2hex` on your Linux or WSL machine (tutorials and repos: [riscv32](https://github.com/johnwinans/riscv-toolchain-install-guide) [elf2hex](https://github.com/sifive/elf2hex)), then you can use the Makefile by changing the source in line 5. Notice that files in the folder test_progs that end with `.c` are C programs and end with `.s` are assembly files. So type `make assembly` if your sources are ended with s and type `make program` if you sources are ended with c. You will get a file called `program.mem`. Add that to the simulation source in Vivado. If you want to remove this .mem file, type `make clean`.
### Simulation
At this stage, you are ready to simulate, just see the output in the Vivado console, it will show the final memory status. (do not delete `program.mem` file when you simulate)
## Reference
The CPU frame, which is a single-cycle one, is from. The stream buffer part is written by my one of my partners Yifan Shen.
