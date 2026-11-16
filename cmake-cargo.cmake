include_guard()

function(find_cargo result)
  find_program(cargo NAMES cargo REQUIRED)

  set(${result} ${cargo})

  return(PROPAGATE ${result})
endfunction()

function(find_rustc result)
  find_program(rustc NAMES rustc REQUIRED)

  set(${result} ${rustc})

  return(PROPAGATE ${result})
endfunction()

function(rust_cpu result)
  if(APPLE AND CMAKE_OSX_ARCHITECTURES)
    set(cpu ${CMAKE_OSX_ARCHITECTURES})
  elseif(MSVC AND CMAKE_GENERATOR_PLATFORM)
    set(cpu ${CMAKE_GENERATOR_PLATFORM})
  elseif(ANDROID AND CMAKE_ANDROID_ARCH_ABI)
    set(cpu ${CMAKE_ANDROID_ARCH_ABI})
  else()
    set(cpu ${CMAKE_SYSTEM_PROCESSOR})
  endif()

  if(NOT cpu)
    set(cpu ${CMAKE_HOST_SYSTEM_PROCESSOR})
  endif()

  string(TOLOWER "${cpu}" cpu)

  if(cpu MATCHES "arm64|aarch64")
    set(cpu "aarch64")
  elseif(cpu MATCHES "armv7-a|armeabi-v7a")
    set(cpu "armv7")
  elseif(cpu MATCHES "x64|x86_64|amd64")
    set(cpu "x86_64")
  elseif(cpu MATCHES "x86|i386|i486|i586|i686")
    set(cpu "i686")
  elseif(cpu MATCHES "wasm32")
    set(cpu "wasm32")
  else()
    message(FATAL_ERROR "Unknown CPU '${cpu}'")
  endif()

  set(${result} ${cpu} PARENT_SCOPE)
endfunction()

function(rust_os result)
  rust_cpu(cpu)

  set(os ${CMAKE_SYSTEM_NAME})

  if(NOT os)
    set(os ${CMAKE_HOST_SYSTEM_NAME})
  endif()

  string(TOLOWER "${os}" os)

  if(os MATCHES "android")
    if(cpu MATCHES "armv7")
      set(os "androideabi")
    endif()
  elseif(os MATCHES "wasi")
    set(os "wasip1")
  elseif(NOT os MATCHES "linux|ios|darwin|windows")
    message(FATAL_ERROR "Unknown OS '${os}'")
  endif()

  set(${result} ${os} PARENT_SCOPE)
endfunction()

function(rust_vendor result)
  rust_os(os)

  if(os MATCHES "darwin|ios")
    set(vendor "apple")
  elseif(os MATCHES "android")
    set(vendor "linux")
  elseif(os MATCHES "windows")
    set(vendor "pc")
  elseif(os MATCHES "wasi")
    set(vendor "")
  else()
    set(vendor "unknown")
  endif()

  set(${result} ${vendor} PARENT_SCOPE)
endfunction()

function(rust_env result)
  rust_cpu(cpu)

  set(env "")

  if(APPLE AND CMAKE_OSX_SYSROOT MATCHES "iPhoneSimulator" AND cpu MATCHES "aarch64")
    set(env "sim")
  elseif(LINUX)
    set(env "gnu")
  elseif(MSVC)
    set(env "msvc")
  endif()

  set(${result} ${env} PARENT_SCOPE)
endfunction()

function(rust_target result)
  rust_cpu(cpu)
  rust_os(os)
  rust_vendor(vendor)
  rust_env(env)

  set(target ${cpu})

  if(vendor)
    set(target ${target}-${vendor})
  endif()

  set(target ${target}-${os})

  if(env)
    set(target ${target}-${env})
  endif()

  set(${result} ${target} PARENT_SCOPE)
endfunction()

# Rust only reports the native libraries that a static library needs when it
# builds one, so build an empty one to find those of the standard library. The
# C runtime that Rust asks for with `/defaultlib` is left to the toolchain.
function(rust_native_static_libs target working_directory result)
  find_rustc(rustc)

  set(probe "${CMAKE_CURRENT_BINARY_DIR}/cmake-cargo/${target}")

  file(WRITE "${probe}/probe.rs" "")

  execute_process(
    COMMAND ${rustc} --crate-type staticlib --target ${target} --print native-static-libs -o "${probe}/probe" "${probe}/probe.rs"
    WORKING_DIRECTORY "${working_directory}"
    ERROR_VARIABLE output
    COMMAND_ERROR_IS_FATAL ANY
  )

  if(NOT output MATCHES "native-static-libs:([^\n]*)")
    message(FATAL_ERROR "No native libraries reported for '${target}'")
  endif()

  separate_arguments(args NATIVE_COMMAND "${CMAKE_MATCH_1}")

  set(libs "")

  while(args)
    list(POP_FRONT args arg)

    if(arg STREQUAL "-framework")
      list(POP_FRONT args framework)

      list(APPEND libs "-framework ${framework}")
    elseif(arg MATCHES "^-l(.+)$")
      list(APPEND libs "${CMAKE_MATCH_1}")
    elseif(arg MATCHES "^(.+)\\.lib$")
      list(APPEND libs "${CMAKE_MATCH_1}")
    elseif(NOT arg MATCHES "^/defaultlib:")
      list(APPEND libs "${arg}")
    endif()
  endwhile()

  list(REMOVE_DUPLICATES libs)

  # The Apple linker always links libSystem and warns when asked to again.
  if(APPLE)
    list(REMOVE_ITEM libs System)
  endif()

  set(${result} ${libs} PARENT_SCOPE)
endfunction()

function(rust_linker_config target result)
  set(config "")

  # Rust drives the Apple and MSVC linkers itself, but links every other target
  # with the host C compiler unless told otherwise.
  if(NOT APPLE AND NOT MSVC AND CMAKE_C_COMPILER_ID MATCHES "Clang")
    set(args "")

    if(CMAKE_C_COMPILER_TARGET)
      list(APPEND args "--target=${CMAKE_C_COMPILER_TARGET}")
    endif()

    if(CMAKE_SYSROOT)
      list(APPEND args "--sysroot=${CMAKE_SYSROOT}")
    endif()

    separate_arguments(flags NATIVE_COMMAND "${CMAKE_C_FLAGS} ${CMAKE_SHARED_LINKER_FLAGS}")

    list(APPEND args ${flags})

    set(rustflags "")

    foreach(arg IN LISTS args)
      toml_string("-Clink-arg=${arg}" arg)

      list(APPEND rustflags "${arg}")
    endforeach()

    list(JOIN rustflags ", " rustflags)

    toml_string("${CMAKE_C_COMPILER}" linker)

    list(APPEND config
      --config "target.${target}.linker=${linker}"
      --config "target.${target}.rustflags=[${rustflags}]"
    )
  endif()

  set(${result} ${config} PARENT_SCOPE)
endfunction()

function(toml_string value result)
  string(REPLACE "\\" "\\\\" value "${value}")
  string(REPLACE "\"" "\\\"" value "${value}")

  set(${result} "\"${value}\"" PARENT_SCOPE)
endfunction()

function(add_crate)
  set(one_value_keywords
    MANIFEST
  )

  cmake_parse_arguments(
    PARSE_ARGV 0 ARGV "" "${one_value_keywords}" ""
  )

  find_cargo(cargo)

  if(ARGV_MANIFEST)
    cmake_path(ABSOLUTE_PATH ARGV_MANIFEST BASE_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}" NORMALIZE)
  else()
    set(ARGV_MANIFEST "${CMAKE_CURRENT_LIST_DIR}/Cargo.toml")
  endif()

  file(REAL_PATH "${ARGV_MANIFEST}" manifest)

  execute_process(
    COMMAND ${cargo} locate-project --workspace --message-format plain --manifest-path "${manifest}"
    OUTPUT_VARIABLE workspace_manifest
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
  )

  cmake_path(CONVERT "${workspace_manifest}" TO_CMAKE_PATH_LIST workspace_manifest NORMALIZE)

  cmake_path(REPLACE_FILENAME workspace_manifest Cargo.lock OUTPUT_VARIABLE lock)

  if(NOT EXISTS ${lock})
    execute_process(
      COMMAND ${cargo} generate-lockfile --manifest-path "${manifest}"
      COMMAND_ERROR_IS_FATAL ANY
    )
  endif()

  execute_process(
    COMMAND ${cargo} metadata --manifest-path "${manifest}" --format-version 1 --no-deps
    OUTPUT_VARIABLE metadata
    COMMAND_ERROR_IS_FATAL ANY
  )

  string(JSON target_directory GET "${metadata}" "target_directory")

  cmake_path(CONVERT "${target_directory}" TO_CMAKE_PATH_LIST target_directory NORMALIZE)

  string(JSON len LENGTH "${metadata}" "packages")

  set(found OFF)

  foreach(i RANGE ${len})
    if(NOT i EQUAL len)
      string(JSON package GET "${metadata}" "packages" ${i})
      string(JSON manifest_path GET "${package}" "manifest_path")

      cmake_path(CONVERT "${manifest_path}" TO_CMAKE_PATH_LIST manifest_path NORMALIZE)

      # Cargo lists every member of the workspace, not just the given package.
      if(manifest_path STREQUAL manifest)
        add_crate_package("${package}" "${target_directory}" "${manifest_path}")

        set(found ON)
      endif()
    endif()
  endforeach()

  if(NOT found)
    message(FATAL_ERROR "No Cargo package found for '${manifest}'")
  endif()
endfunction()

function(add_crate_package package target_directory manifest_path)
  string(JSON len LENGTH "${package}" "targets")

  foreach(i RANGE ${len})
    if(NOT i EQUAL len)
      string(JSON target GET "${package}" "targets" ${i})

      add_crate_target("${target}" "${target_directory}" "${manifest_path}")
    endif()
  endforeach()
endfunction()

function(add_crate_target target target_directory manifest_path)
  string(JSON name GET "${target}" "name")
  string(JSON kind GET "${target}" "kind" "0")

  if(kind MATCHES "custom-build")
    return()
  endif()

  if(kind STREQUAL "staticlib")
    add_library(${name} STATIC IMPORTED)

    if(WIN32)
      set(artifact "${name}.lib")
    else()
      set(artifact "lib${name}.a")
    endif()
  else()
    message(FATAL_ERROR "Unknown Cargo target kind '${kind}'")
  endif()

  rust_target(target)

  set(output "${target_directory}/${target}")
  set(debug_output "${output}/debug/${artifact}")
  set(release_output "${output}/release/${artifact}")

  set_target_properties(
    ${name}
    PROPERTIES
    IMPORTED_CONFIGURATIONS "DEBUG;RELEASE"
    IMPORTED_LOCATION_DEBUG "${debug_output}"
    IMPORTED_LOCATION_RELEASE "${release_output}"
    MAP_IMPORTED_CONFIG_MINSIZEREL Release
    MAP_IMPORTED_CONFIG_RELWITHDEBINFO Release
  )

  cmake_path(GET manifest_path PARENT_PATH working_directory)

  rust_native_static_libs(${target} "${working_directory}" libs)

  target_link_libraries(${name} INTERFACE ${libs})

  rust_linker_config(${target} config)

  add_custom_target(
    ${name}_build
    COMMAND ${cargo} build --target ${target} ${config} $<$<NOT:$<CONFIG:Debug>>:--release>
    WORKING_DIRECTORY ${working_directory}
    BYPRODUCTS "$<IF:$<CONFIG:Debug>,${debug_output},${release_output}>"
    VERBATIM
    COMMAND_EXPAND_LISTS
  )

  add_dependencies(${name} ${name}_build)
endfunction()
