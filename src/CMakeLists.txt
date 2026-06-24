# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(kokoro_tts_library VERSION 0.0.1 LANGUAGES C CXX)

# ---- onnxruntime ---
set(ONNXRUNTIME_VERSION "1.20.0")
if(ANDROID)
    set(ONNXRUNTIME_PREFIX "onnxruntime-android-${ONNXRUNTIME_VERSION}")
    set(ONNXRUNTIME_EXT "aar")
    set(ONNXRUNTIME_URL "https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/${ONNXRUNTIME_VERSION}/onnxruntime-android-${ONNXRUNTIME_VERSION}.aar")
elseif(APPLE)
    set(ONNXRUNTIME_PREFIX "onnxruntime-osx-arm64-${ONNXRUNTIME_VERSION}")
    set(ONNXRUNTIME_EXT "tgz")
    set(ONNXRUNTIME_URL "https://github.com/microsoft/onnxruntime/releases/download/v${ONNXRUNTIME_VERSION}/${ONNXRUNTIME_PREFIX}.${ONNXRUNTIME_EXT}")
endif()

set(ONNXRUNTIME_FILENAME "${ONNXRUNTIME_PREFIX}.${ONNXRUNTIME_EXT}")
set(ONNXRUNTIME_DIR "${CMAKE_CURRENT_LIST_DIR}/lib/${ONNXRUNTIME_PREFIX}")

if(NOT EXISTS "${ONNXRUNTIME_DIR}")
    if(NOT EXISTS "${CMAKE_CURRENT_LIST_DIR}/download/${ONNXRUNTIME_FILENAME}")
        file(DOWNLOAD "${ONNXRUNTIME_URL}" "${CMAKE_CURRENT_LIST_DIR}/download/${ONNXRUNTIME_FILENAME}")
    endif()
    if(ANDROID)
        file(ARCHIVE_EXTRACT INPUT "${CMAKE_CURRENT_LIST_DIR}/download/${ONNXRUNTIME_FILENAME}" DESTINATION "${ONNXRUNTIME_DIR}")
    else()
        file(ARCHIVE_EXTRACT INPUT "${CMAKE_CURRENT_LIST_DIR}/download/${ONNXRUNTIME_FILENAME}" DESTINATION "${CMAKE_CURRENT_LIST_DIR}/lib")
    endif()
endif()

# ---- espeak-ng ---
set(USE_ASYNC OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(USE_MBROLA OFF CACHE BOOL "" FORCE)
set(USE_LIBSONIC OFF CACHE BOOL "" FORCE)
set(USE_LIBPCAUDIO OFF CACHE BOOL "" FORCE)
set(USE_KLATT OFF CACHE BOOL "" FORCE)
set(USE_SPEECHPLAYER OFF CACHE BOOL "" FORCE)
set(COMPILE_INTONATIONS OFF CACHE BOOL "" FORCE)
set(ENABLE_TESTS OFF CACHE BOOL "" FORCE)
set(EXTRA_cmn ON CACHE BOOL "" FORCE)
set(EXTRA_ru ON CACHE BOOL "" FORCE)

add_subdirectory(espeak-ng)

add_library(kokoro_tts SHARED
  "kokoro_tts.cpp"
  "audio_data.cpp"
)

set_target_properties(kokoro_tts PROPERTIES
  PUBLIC_HEADER kokoro_tts.h
  OUTPUT_NAME "kokoro_tts"
)

target_include_directories(kokoro_tts PUBLIC 
    ${CMAKE_CURRENT_LIST_DIR}/espeak-ng/src/include
)

if(APPLE)
    target_include_directories(kokoro_tts PUBLIC ${ONNXRUNTIME_DIR}/include)
    target_link_directories(kokoro_tts PUBLIC ${ONNXRUNTIME_DIR}/lib)
    target_link_libraries(kokoro_tts PUBLIC espeak-ng onnxruntime)
elseif(ANDROID)
    target_include_directories(kokoro_tts PUBLIC ${ONNXRUNTIME_DIR}/headers)
    target_link_directories(kokoro_tts PUBLIC ${ONNXRUNTIME_DIR}/jni/${ANDROID_ABI})
    target_link_libraries(kokoro_tts PUBLIC espeak-ng onnxruntime log)
endif()

target_compile_definitions(kokoro_tts PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(kokoro_tts PRIVATE "-Wl,-z,max-page-size=16384")
endif()
