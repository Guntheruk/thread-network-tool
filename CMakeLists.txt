cmake_minimum_required(VERSION 3.16)
project(thread_network_tool VERSION 1.0.0 LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
option(TNT_WITH_COMMISSIONER "Build optional OpenThread read-only probe" OFF)
option(TNT_BUILD_MOVE_LAB "Build isolated loopback-only native move lab worker" OFF)
option(TNT_BUILD_APP_MOVE_LAB "Build isolated app move lab worker" OFF)
option(TNT_BUILD_MAC_MOVE_WORKER "Build opt-in Mac source-network move worker" OFF)
option(TNT_BUILD_MAC_MOVE_FIXTURE "Build opt-in loopback-only mutable DTLS test fixture" OFF)
option(TNT_BUILD_TESTS "Build native tests" ON)
option(TNT_BUILD_MOVE_JOURNAL "Build private POSIX move journal helper (no network access)" OFF)
option(TNT_BUILD_MACOS_PROBE_FIXTURE "Build isolated loopback DTLS probe fixture" OFF)
if(TNT_BUILD_TESTS)
  enable_testing()
endif()
add_library(thread_network_core SHARED native/dataset.cpp)
target_compile_definitions(thread_network_core PRIVATE TNT_BUILDING_CORE)
target_include_directories(thread_network_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/native)
add_executable(thread-network native/cli.cpp native/discovery.cpp)
if(WIN32)
  # The DLL exports only its C ABI; the CLI also needs private C++ parser symbols.
  # Compile the parser into the CLI instead of exporting its std::string ABI.
  target_sources(thread-network PRIVATE native/dataset.cpp)
  target_compile_definitions(thread-network PRIVATE TNT_BUILDING_CORE)
else()
  target_link_libraries(thread-network PRIVATE thread_network_core)
endif()
if(APPLE)
  # An installed helper lives in Contents/Helpers and finds its core in
  # Contents/Frameworks. Build-tree targets keep CMake's separate build RPATH.
  set_target_properties(thread_network_core PROPERTIES
    MACOSX_RPATH ON
    INSTALL_NAME_DIR "@rpath")
  set_target_properties(thread-network PROPERTIES
    INSTALL_RPATH "@executable_path/../Frameworks")
  target_link_libraries(thread-network PRIVATE "-framework CoreServices")
endif()
if(APPLE)
  install(TARGETS thread_network_core LIBRARY DESTINATION Frameworks)
  install(TARGETS thread-network RUNTIME DESTINATION Helpers)
endif()
if(TNT_WITH_COMMISSIONER)
  if(WIN32)
    message(FATAL_ERROR "Commissioner probe is not validated on Windows")
  endif()
  if(NOT TNT_COMMISSIONER_SOURCE OR NOT EXISTS "${TNT_COMMISSIONER_SOURCE}/CMakeLists.txt")
    message(FATAL_ERROR "Set TNT_COMMISSIONER_SOURCE to the pinned OpenThread Commissioner checkout")
  endif()
  find_package(Python3 3.10 REQUIRED COMPONENTS Interpreter)
  execute_process(COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tools/prepare_commissioner_source.py"
    --verify-only --output "${TNT_COMMISSIONER_SOURCE}" RESULT_VARIABLE TNT_SOURCE_RESULT OUTPUT_QUIET)
  if(NOT TNT_SOURCE_RESULT EQUAL 0)
    message(FATAL_ERROR "Use verified generated Commissioner source from tools/prepare_commissioner_source.py")
  endif()
  add_custom_target(tnt-verify-commissioner-source
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tools/prepare_commissioner_source.py"
      --verify-only --output "${TNT_COMMISSIONER_SOURCE}"
    COMMENT "Verify pinned generated Commissioner provenance")
  set(ENV{PYTHONDONTWRITEBYTECODE} 1)
  set(OT_COMM_APP OFF CACHE BOOL "" FORCE)
  set(OT_COMM_CCM OFF CACHE BOOL "" FORCE)
  set(OT_COMM_TEST OFF CACHE BOOL "" FORCE)
  set(OT_COMM_JAVA_BINDING OFF CACHE BOOL "" FORCE)
  # Dependencies stay local to this build; do not update a user-wide registry.
  set(CMAKE_EXPORT_NO_PACKAGE_REGISTRY ON)
  # Pinned Commissioner hardcodes libfmt.a even in Debug configurations.
  set(FMT_DEBUG_POSTFIX "" CACHE STRING "" FORCE)
  add_subdirectory("${TNT_COMMISSIONER_SOURCE}" "${CMAKE_CURRENT_BINARY_DIR}/ot-commissioner" EXCLUDE_FROM_ALL)
  add_dependencies(commissioner tnt-verify-commissioner-source)
  if(APPLE)
    # Pinned upstream mbedTLS trips a newer AppleClang diagnostic treated as an error.
    target_compile_options(mbedx509 PRIVATE -Wno-error=uninitialized-const-pointer)
  endif()
  target_sources(thread-network PRIVATE native/probe.cpp)
  target_include_directories(thread-network PRIVATE "${TNT_COMMISSIONER_SOURCE}/include")
  target_compile_definitions(thread-network PRIVATE TNT_WITH_COMMISSIONER)
  target_link_libraries(thread-network PRIVATE commissioner)
  if(TNT_BUILD_MACOS_PROBE_FIXTURE)
    if(NOT APPLE)
      message(FATAL_ERROR "Mac probe fixture requires macOS")
    endif()
    add_executable(tnt-macos-probe-fixture tests/native/macos_probe_fixture.cpp)
    target_include_directories(tnt-macos-probe-fixture PRIVATE
      "${TNT_COMMISSIONER_SOURCE}/include" "${TNT_COMMISSIONER_SOURCE}/src"
      "${TNT_COMMISSIONER_SOURCE}/third_party/libevent/repo/include"
      "${CMAKE_CURRENT_BINARY_DIR}/ot-commissioner/third_party/libevent/repo/include"
      "${TNT_COMMISSIONER_SOURCE}/third_party/mbedtls/repo/include")
    target_link_libraries(tnt-macos-probe-fixture PRIVATE commissioner fmt::fmt event_core mbedtls)
  endif()
  if(TNT_BUILD_TESTS)
    add_executable(tnt-commissioner-codec-tests patches/commissioner/tests/test_legacy_wakeup.cpp)
    target_include_directories(tnt-commissioner-codec-tests PRIVATE "${TNT_COMMISSIONER_SOURCE}/src")
    target_link_libraries(tnt-commissioner-codec-tests PRIVATE commissioner fmt::fmt event_core mbedtls)
    add_test(NAME native-commissioner-codec COMMAND tnt-commissioner-codec-tests)
    add_executable(tnt-move-adapter-tests tests/native/test_network_move_commissioner.cpp native/network_move.cpp)
    target_include_directories(tnt-move-adapter-tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/native "${TNT_COMMISSIONER_SOURCE}/include")
    target_link_libraries(tnt-move-adapter-tests PRIVATE thread_network_core commissioner)
    add_test(NAME native-move-adapter COMMAND tnt-move-adapter-tests)
    add_executable(tnt-probe-metadata-tests tests/native/test_probe_metadata.cpp native/probe.cpp)
    target_include_directories(tnt-probe-metadata-tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/native "${TNT_COMMISSIONER_SOURCE}/include")
    target_link_libraries(tnt-probe-metadata-tests PRIVATE thread_network_core commissioner)
    add_test(NAME native-probe-metadata COMMAND tnt-probe-metadata-tests)
  endif()
endif()
if(TNT_BUILD_TESTS)
  enable_testing()
  add_executable(tnt-native-tests tests/native/test_dataset.cpp)
  target_link_libraries(tnt-native-tests PRIVATE thread_network_core)
  add_test(NAME native-dataset COMMAND tnt-native-tests)
  add_executable(tnt-discovery-tests tests/native/test_discovery.cpp native/discovery.cpp)
  target_include_directories(tnt-discovery-tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/native)
  if(APPLE)
    target_link_libraries(tnt-discovery-tests PRIVATE "-framework CoreServices")
  endif()
  add_test(NAME native-discovery COMMAND tnt-discovery-tests)
  add_test(NAME native-capabilities COMMAND thread-network capabilities)
  set_tests_properties(native-capabilities PROPERTIES
    PASS_REGULAR_EXPRESSION "\"network_writes\":false")
endif()

# No mutation entry point is added to the application CLI or installed payload.
if(TNT_BUILD_MOVE_LAB OR TNT_BUILD_APP_MOVE_LAB OR TNT_BUILD_MAC_MOVE_WORKER)
  if(NOT TNT_WITH_COMMISSIONER OR WIN32)
    message(FATAL_ERROR "Isolated move workers require the pinned Commissioner on POSIX")
  endif()
  add_library(tnt-network-move STATIC native/network_move.cpp)
  target_include_directories(tnt-network-move PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/native)
  target_link_libraries(tnt-network-move PUBLIC thread_network_core)
  if(TNT_BUILD_MOVE_LAB)
    add_executable(thread-network-move-lab native/network_move_lab_main.cpp native/network_move_commissioner.cpp)
    target_include_directories(thread-network-move-lab PRIVATE "${TNT_COMMISSIONER_SOURCE}/include")
    target_link_libraries(thread-network-move-lab PRIVATE tnt-network-move commissioner)
  endif()
  if(TNT_BUILD_APP_MOVE_LAB)
    add_executable(thread-network-move-app
      native/network_move_worker_main.cpp
      native/network_move_worker_protocol.cpp
      native/network_move_worker_fixture.cpp
      native/network_move_worker_lifecycle.cpp
      native/network_move_commissioner.cpp)
    target_include_directories(thread-network-move-app PRIVATE "${TNT_COMMISSIONER_SOURCE}/include" "${TNT_COMMISSIONER_SOURCE}/third_party/mbedtls/repo/include")
    target_link_libraries(thread-network-move-app PRIVATE tnt-network-move commissioner)
    if(TNT_BUILD_TESTS)
      add_executable(tnt-move-app-protocol-tests
        tests/native/test_network_move_worker_protocol.cpp
        native/network_move_worker_protocol.cpp)
      target_include_directories(tnt-move-app-protocol-tests PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/native"
        "${TNT_COMMISSIONER_SOURCE}/third_party/mbedtls/repo/include")
      target_link_libraries(tnt-move-app-protocol-tests PRIVATE tnt-network-move commissioner)
      add_test(NAME native-move-app-protocol COMMAND tnt-move-app-protocol-tests)
      add_executable(tnt-move-app-lifecycle-tests
        tests/native/test_network_move_worker_lifecycle.cpp
        native/network_move_worker_lifecycle.cpp)
      target_include_directories(tnt-move-app-lifecycle-tests PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/native")
      add_test(NAME native-move-app-lifecycle COMMAND tnt-move-app-lifecycle-tests)
      add_executable(tnt-move-app-socket-owner-tests
        tests/native/test_network_move_worker_socket_owner.cpp
        native/network_move_worker_fixture.cpp)
      target_include_directories(tnt-move-app-socket-owner-tests PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/native")
    endif()
  endif()
  if(TNT_BUILD_MAC_MOVE_WORKER)
    if(NOT APPLE)
      message(FATAL_ERROR "Mac source-network worker requires macOS")
    endif()
    add_executable(tnt-mac-move-worker
      native/mac_move_worker_main.cpp
      native/mac_move_worker_protocol.cpp
      native/network_move_commissioner.cpp
      native/network_move_worker_lifecycle.cpp
      native/move_journal.cpp)
    target_include_directories(tnt-mac-move-worker PRIVATE
      "${TNT_COMMISSIONER_SOURCE}/include"
      "${TNT_COMMISSIONER_SOURCE}/third_party/mbedtls/repo/include")
    target_link_libraries(tnt-mac-move-worker PRIVATE tnt-network-move commissioner)
    set_target_properties(tnt-mac-move-worker PROPERTIES INSTALL_RPATH "@executable_path/../Frameworks")
    install(TARGETS tnt-mac-move-worker RUNTIME DESTINATION Helpers)
    if(TNT_BUILD_TESTS)
      add_executable(tnt-mac-move-protocol-tests
        tests/native/test_mac_move_worker_protocol.cpp
        native/mac_move_worker_protocol.cpp
        native/move_journal.cpp)
      target_include_directories(tnt-mac-move-protocol-tests PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/native"
        "${TNT_COMMISSIONER_SOURCE}/third_party/mbedtls/repo/include")
      target_link_libraries(tnt-mac-move-protocol-tests PRIVATE tnt-network-move commissioner)
      add_test(NAME native-mac-move-protocol COMMAND tnt-mac-move-protocol-tests)
      add_executable(tnt-mac-move-lifecycle-tests
        tests/native/test_network_move_worker_lifecycle.cpp
        native/network_move_worker_lifecycle.cpp)
      target_include_directories(tnt-mac-move-lifecycle-tests PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/native")
      add_test(NAME native-mac-move-lifecycle COMMAND tnt-mac-move-lifecycle-tests)
      add_test(NAME native-mac-move-capabilities COMMAND tnt-mac-move-worker capabilities)
      set_tests_properties(native-mac-move-capabilities PROPERTIES
        PASS_REGULAR_EXPRESSION "\"network_writes\":true")
    endif()
  endif()
endif()

if(TNT_BUILD_MAC_MOVE_FIXTURE)
  if(NOT APPLE OR NOT TNT_WITH_COMMISSIONER)
    message(FATAL_ERROR "Mutable Mac test fixture requires macOS and the pinned Commissioner")
  endif()
  add_executable(tnt-mac-move-write-fixture tests/native/mac_move_write_fixture.cpp)
  target_include_directories(tnt-mac-move-write-fixture PRIVATE
    "${TNT_COMMISSIONER_SOURCE}/include" "${TNT_COMMISSIONER_SOURCE}/src"
    "${TNT_COMMISSIONER_SOURCE}/third_party/libevent/repo/include"
    "${CMAKE_CURRENT_BINARY_DIR}/ot-commissioner/third_party/libevent/repo/include"
    "${TNT_COMMISSIONER_SOURCE}/third_party/mbedtls/repo/include")
  target_link_libraries(tnt-mac-move-write-fixture PRIVATE commissioner fmt::fmt event_core mbedtls)
  if(TNT_BUILD_TESTS AND TNT_BUILD_MAC_MOVE_WORKER)
    add_test(NAME native-mac-move-wire
      COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/tools/test_mac_move_wire.py"
      "$<TARGET_FILE:tnt-mac-move-worker>" "$<TARGET_FILE:tnt-mac-move-write-fixture>")
  endif()
endif()

if(TNT_BUILD_TESTS)
  add_executable(tnt-network-move-tests tests/native/test_network_move.cpp native/network_move.cpp)
  target_include_directories(tnt-network-move-tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/native)
  if(WIN32)
    # The guard also uses private parser symbols, outside the DLL's C ABI.
    target_sources(tnt-network-move-tests PRIVATE native/dataset.cpp)
    target_compile_definitions(tnt-network-move-tests PRIVATE TNT_BUILDING_CORE)
  else()
    target_link_libraries(tnt-network-move-tests PRIVATE thread_network_core)
  endif()
  add_test(NAME native-network-move COMMAND tnt-network-move-tests)
endif()

# Explicit opt-in; no application dispatch entry point or default installed worker.
if(TNT_BUILD_MOVE_JOURNAL)
  if(WIN32)
    message(FATAL_ERROR "Native move journal requires POSIX")
  endif()
  add_executable(thread-move-journal native/move_journal.cpp native/move_journal_cli.cpp)
  if(APPLE)
    install(TARGETS thread-move-journal RUNTIME DESTINATION Helpers)
  endif()
  if(TNT_BUILD_TESTS)
    add_executable(tnt-move-journal-fault native/move_journal.cpp tests/native/move_journal_fault.cpp)
    target_include_directories(tnt-move-journal-fault PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/native)
  endif()
endif()
