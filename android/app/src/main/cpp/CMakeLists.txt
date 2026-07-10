# android/app/src/main/cpp/CMakeLists.txt
# NDK build configuration for SightMate native libraries
#
# Builds 'sightmate_cv' shared library containing the OpenCV optical flow wrapper.
# OpenCV4Android is optional — if not present, the library still builds and exports
# the JNI symbol; computeOpticalFlowNative returns zero ego-motion gracefully.
#
# To enable full OpenCV support:
#   1. Download OpenCV4Android SDK from https://opencv.org/releases/
#   2. Extract to android/opencv/
#   3. Uncomment the OpenCV include/link lines below

cmake_minimum_required(VERSION 3.22.1)
project("sightmate_cv" VERSION 1.0.0)

# ── C++ standard ───────────────────────────────────────────────────────────────

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── OpenCV integration (optional) ─────────────────────────────────────────────

set(OPENCV_SDK_DIR "${CMAKE_SOURCE_DIR}/../../../../../opencv")
set(OPENCV_AVAILABLE FALSE)

if(EXISTS "${OPENCV_SDK_DIR}/sdk/native/jni/OpenCVConfig.cmake")
    set(OpenCV_DIR "${OPENCV_SDK_DIR}/sdk/native/jni")
    find_package(OpenCV REQUIRED core imgproc video)

    if(OpenCV_FOUND)
        set(OPENCV_AVAILABLE TRUE)
        message(STATUS "OpenCV ${OpenCV_VERSION} found — optical flow ENABLED")
        add_compile_definitions(HAVE_OPENCV)
    endif()
else()
    message(WARNING "OpenCV SDK not found at ${OPENCV_SDK_DIR}. Optical flow disabled.")
    message(WARNING "To enable: extract OpenCV4Android SDK to android/opencv/")
endif()

# ── Source files ───────────────────────────────────────────────────────────────

add_library(
    sightmate_cv
    SHARED
    optical_flow_wrapper.cpp
)

# ── Include directories ────────────────────────────────────────────────────────

target_include_directories(sightmate_cv PRIVATE
    ${CMAKE_SOURCE_DIR}
)

if(OPENCV_AVAILABLE)
    target_include_directories(sightmate_cv PRIVATE ${OpenCV_INCLUDE_DIRS})
endif()

# ── Link libraries ────────────────────────────────────────────────────────────

find_library(log-lib log)
find_library(android-lib android)

target_link_libraries(sightmate_cv
    ${log-lib}
    ${android-lib}
)

if(OPENCV_AVAILABLE)
    target_link_libraries(sightmate_cv ${OpenCV_LIBS})
endif()

# ── Compiler optimizations ────────────────────────────────────────────────────

target_compile_options(sightmate_cv PRIVATE
    -O3                   # Maximum optimization
    -ffast-math           # Fast floating point (safe for vision ops)
    -funroll-loops        # Loop unrolling
    -fomit-frame-pointer  # Save registers
    -Wall
    -Wno-unused-parameter
)
