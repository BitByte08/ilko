cmake_minimum_required(VERSION 3.22)
project(ilko LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

set(ILKO_VERSION "1.0.0")

find_package(Qt6 REQUIRED COMPONENTS Widgets Multimedia Core Gui DBus Network)
find_package(ECM 6.0.0 REQUIRED NO_MODULE)

set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
remove_definitions(-DQT_NO_KEYWORDS)
remove_definitions(-DQT_NO_CAST_FROM_ASCII)
remove_definitions(-DQT_NO_CAST_TO_ASCII)
remove_definitions(-DQT_NO_CAST_FROM_BYTEARRAY)
remove_definitions(-DQT_NO_URL_CAST_FROM_STRING)
remove_definitions(-DQT_STRICT_ITERATORS)
remove_definitions(-DQT_NO_NARROWING_CONVERSIONS_IN_CONNECT)

find_package(KF6 REQUIRED COMPONENTS
    I18n
)

find_package(Plasma REQUIRED)

set(PLUGIN_ID "org.bssm.ilko.video")

add_subdirectory(src)

install(TARGETS ilko DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES data/ilko.desktop DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/applications)
install(FILES data/ilko.png
    DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/icons/hicolor/512x512/apps)

plasma_install_package(package ${PLUGIN_ID} wallpapers)
