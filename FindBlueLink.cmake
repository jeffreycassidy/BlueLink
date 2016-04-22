SET(BlueLink_ROOT "/home/parallels/src/BlueLink" CACHE PATH "")

SET(BlueLink_INCLUDE_DIRS "${BlueLink_ROOT}/Host" CACHE PATH "")
SET(BlueLink_LIBRARY_DIRS "${BlueLink_ROOT}/Build/Release/" CACHE PATH "")

LIST(APPEND BlueLink_LIBRARIES BlueLinkHost)

LINK_DIRECTORIES(${BlueLink_LIBRARY_DIRS})
