//
//  SimulatorPluginLibrary.h
//  plugin_opus
//

#ifndef _SimulatorPluginLibrary_H__
#define _SimulatorPluginLibrary_H__

#include <CoronaLua.h>
#include <CoronaMacros.h>

// Экспортируемая функция инициализации библиотеки в Lua
CORONA_EXPORT int luaopen_plugin_opus( lua_State *L );

#endif // _SimulatorPluginLibrary_H__
