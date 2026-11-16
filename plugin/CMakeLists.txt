cmake_minimum_required(VERSION 3.20)
project(DreadmoorVRPlugin CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

add_executable(test_core tests/test_core.cpp)
target_include_directories(test_core PRIVATE src)

if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/src/Plugin.cpp)
    add_library(DreadmoorVR SHARED src/Plugin.cpp)
    target_include_directories(DreadmoorVR PRIVATE src third_party third_party/uevr third_party/openvr)
    target_compile_definitions(DreadmoorVR PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
endif()
