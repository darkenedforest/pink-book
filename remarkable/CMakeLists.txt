cmake_minimum_required(VERSION 3.21)
project(PinkBookReader VERSION 0.1.0 LANGUAGES CXX)

find_package(Qt6 6.2 REQUIRED COMPONENTS Quick)
find_program(NODE_EXECUTABLE NAMES node nodejs REQUIRED)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

get_filename_component(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
set(CONTENT_DIR "${CMAKE_CURRENT_BINARY_DIR}/content")
file(GLOB_RECURSE CONTENT_SOURCES CONFIGURE_DEPENDS "${REPO_ROOT}/*.html")
file(GLOB COVER_SOURCES CONFIGURE_DEPENDS
    "${REPO_ROOT}/bookshelf/*.png"
    "${REPO_ROOT}/bookshelf/*.jpg"
    "${REPO_ROOT}/bookshelf/*.jpeg"
    "${REPO_ROOT}/bookshelf/*.webp")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    ${CONTENT_SOURCES}
    "${REPO_ROOT}/bookshelf/index.html"
    "${CMAKE_CURRENT_SOURCE_DIR}/tools/export-content.mjs")
# Reconfigure whenever a chapter changes, so the Qt resource manifest and files
# are generated before either the host or the tablet build starts.
file(REMOVE_RECURSE "${CONTENT_DIR}")
execute_process(
    COMMAND "${NODE_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tools/export-content.mjs"
            "${REPO_ROOT}" "${CONTENT_DIR}"
    COMMAND_ERROR_IS_FATAL ANY)
file(GLOB CONTENT_JSON "${CONTENT_DIR}/*.json")
if(NOT EXISTS "${CONTENT_DIR}/catalog.json")
    message(FATAL_ERROR "Book exporter did not generate catalog.json")
endif()
set(CONTENT_COVERS)
foreach(cover IN LISTS COVER_SOURCES)
    get_filename_component(name "${cover}" NAME)
    configure_file("${cover}" "${CONTENT_DIR}/${name}" COPYONLY)
    list(APPEND CONTENT_COVERS "${CONTENT_DIR}/${name}")
endforeach()

set(PINK_BOOK_JAPANESE_FONT "" CACHE FILEPATH "Optional licensed Japanese font to compile into the reader")
if(PINK_BOOK_JAPANESE_FONT)
    if(NOT EXISTS "${PINK_BOOK_JAPANESE_FONT}")
        message(FATAL_ERROR "PINK_BOOK_JAPANESE_FONT must name an existing font")
    endif()
    configure_file("${PINK_BOOK_JAPANESE_FONT}" "${CONTENT_DIR}/Japanese.ttf" COPYONLY)
    list(APPEND CONTENT_JSON "${CONTENT_DIR}/Japanese.ttf")
endif()

qt_add_executable(pink-book-reader main.cpp)
target_link_libraries(pink-book-reader PRIVATE Qt6::Quick)
qt_add_resources(pink-book-reader reader_ui PREFIX "/" FILES Main.qml ReaderButton.qml)
qt_add_resources(pink-book-reader reader_content BIG_RESOURCES
    PREFIX "/content" BASE "${CONTENT_DIR}"
    FILES ${CONTENT_JSON} ${CONTENT_COVERS})
install(TARGETS pink-book-reader RUNTIME DESTINATION .)
install(PROGRAMS run-on-tablet.sh DESTINATION .)

enable_testing()
add_test(NAME content-export COMMAND "${NODE_EXECUTABLE}" --test
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/export-content.test.mjs")
find_program(SH_EXECUTABLE NAMES sh)
if(SH_EXECUTABLE)
    add_test(NAME tablet-launcher COMMAND "${SH_EXECUTABLE}"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/test-launcher.sh")
endif()
if(NOT CMAKE_CROSSCOMPILING)
    add_test(NAME embedded-content COMMAND pink-book-reader --check-content)
    add_test(NAME persisted-progress COMMAND "${CMAKE_COMMAND}"
        "-DREADER=$<TARGET_FILE:pink-book-reader>"
        "-DCHECKPOINT=${CMAKE_CURRENT_BINARY_DIR}/test-progress.ini"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/test-progress.cmake")
    set_tests_properties(embedded-content persisted-progress PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
