set(ILKO_SOURCES
    main.cpp
    core/ProfileManager.cpp
    core/NetworkWatcher.cpp
    core/SwitchController.cpp
    ui/MainWindow.cpp
    resources.qrc
)

set(ILKO_HEADERS
    core/ProfileManager.h
    core/NetworkWatcher.h
    core/SwitchController.h
    ui/MainWindow.h
)

add_executable(ilko ${ILKO_SOURCES} ${ILKO_HEADERS})

target_link_libraries(ilko PRIVATE
    Qt6::Widgets
    Qt6::Multimedia
    Qt6::Core
    Qt6::Gui
    Qt6::DBus
    Qt6::Network
)

target_compile_definitions(ilko PRIVATE
    QT_DISABLE_DEPRECATED_BEFORE=0x060000
)

install(TARGETS ilko DESTINATION bin)