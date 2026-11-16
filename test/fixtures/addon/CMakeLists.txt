cmake_minimum_required(VERSION 3.25)

find_package(cmake-bare REQUIRED PATHS node_modules/cmake-bare)
find_package(cmake-cargo REQUIRED PATHS node_modules/cmake-cargo)

project(cargo_addon C)

add_crate()

add_bare_module(addon)

target_sources(
  ${addon}
  PRIVATE
    binding.c
)

target_link_libraries(
  ${addon}
  PRIVATE
    answer
)
