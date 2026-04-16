cmake_minimum_required(VERSION 3.22)
project(ilko LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

set(ILKO_VERSION "1.0.0")

find_package(Qt6 REQUIRED COMPONENTS Widgets Multimedia Core Gui DBus Network)

add_subdirectory(src)

install(TARGETS ilko DESTINATION bin)
install(FILES data/ilko.desktop data/ilko.png DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/applications)