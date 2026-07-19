add_executable(${CMAKE_PROJECT_NAME} main.cpp resources.qrc)
target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE Asteroid::AsteroidApp6)
install(TARGETS ${CMAKE_PROJECT_NAME}
        DESTINATION ${CMAKE_INSTALL_BINDIR})

file(GLOB SOUND_FILES "${CMAKE_CURRENT_SOURCE_DIR}/*.wav")
install(FILES ${SOUND_FILES}
        DESTINATION /usr/share/sounds)

file(GLOB NGF_EVENT_FILES "${CMAKE_CURRENT_SOURCE_DIR}/events.d/*.ini")
install(FILES ${NGF_EVENT_FILES}
        DESTINATION /usr/share/ngfd/events.d)
