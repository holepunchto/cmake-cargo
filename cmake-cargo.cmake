include_guard()

function(find_cargo result)
  find_program(cargo NAMES cargo REQUIRED)

  set(${result} ${cargo})

  return(PROPAGATE ${result})
endfunction()

function(rust_os result)
  set(os ${CMAKE_SYSTEM_NAME})

  if(NOT os)
    set(os ${CMAKE_HOST_SYSTEM_NAME})
  endif()

  string(TOLOWER "${os}" os)

  if(NOT os MATCHES "android|linux|ios|darwin|windows")
    message(FATAL_ERROR "Unknown OS '${os}'")
  endif()

  set(${result} ${os} PARENT_SCOPE)
endfunction()

function(rust_vendor result)
  rust_os(os)

  if(os MATCHES "darwin")
    set(vendor "apple")
  elseif(os MATCHES "windows")
    set(vendor "pc")
  else()
    set(vendor "unknown")
  endif()

  set(${result} ${vendor} PARENT_SCOPE)
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
    set(cpu "arm")
  elseif(cpu MATCHES "x64|x86_64|amd64")
    set(cpu "x86_64")
  elseif(cpu MATCHES "x86|i386|i486|i586|i686")
    set(cpu "x86")
  else()
    message(FATAL_ERROR "Unknown CPU '${cpu}'")
  endif()

  set(${result} ${cpu} PARENT_SCOPE)
endfunction()

function(rust_target result)
  rust_os(os)
  rust_vendor(vendor)
  rust_cpu(cpu)

  set(${result} "${cpu}-${vendor}-${os}" PARENT_SCOPE)
endfunction()

function(add_crate)
  set(one_value_keywords
    MANIFEST
  )

  cmake_parse_arguments(
    PARSE_ARGV 1 ARGV "" "${one_value_keywords}" ""
  )

  find_cargo(cargo)

  if(ARGV_MANIFEST)
    cmake_path(ABSOLUTE_PATH ARGV_MANIFEST BASE_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}" NORMALIZE)
  else()
    set(ARGV_MANIFEST "${CMAKE_CURRENT_LIST_DIR}/Cargo.toml")
  endif()

  set(manifest "${ARGV_MANIFEST}")

  cmake_path(REPLACE_FILENAME manifest Cargo.lock OUTPUT_VARIABLE lock)

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

  string(JSON len LENGTH "${metadata}" "packages")

  foreach(i RANGE ${len})
    if(NOT i EQUAL len)
      string(JSON package GET "${metadata}" "packages" ${i})

      add_crate_package("${package}" "${target_directory}")
    endif()
  endforeach()
endfunction()

function(add_crate_package package target_directory)
  string(JSON len LENGTH "${package}" "targets")

  foreach(i RANGE ${len})
    if(NOT i EQUAL len)
      string(JSON target GET "${package}" "targets" ${i})

      add_crate_target("${target}" "${target_directory}")
    endif()
  endforeach()
endfunction()

function(add_crate_target target target_directory)
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

  rust_target(output)

  set(output "${target_directory}/${output}")

  set_target_properties(
    ${name}
    PROPERTIES
    IMPORTED_CONFIGURATIONS "DEBUG;RELEASE"
    IMPORTED_LOCATION_DEBUG "${output}/debug/${artifact}"
    IMPORTED_LOCATION_RELEASE "${output}/release/${artifact}"
    MAP_IMPORTED_CONFIG_MINSIZEREL Release
    MAP_IMPORTED_CONFIG_RELWITHDEBINFO Release
  )
endfunction()
