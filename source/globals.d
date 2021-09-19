module globals;

import glfw3.api;
import erupted;
import gl3n.linalg;

import core.time;

/**

    This module contains global state pertaining to the program itself, not the
    game state. It should be imported with a 'static import' command, so all its
    members must be prefixed with 'globals.' to be accessed.

**/
extern (C) nothrow @nogc:

bool  windowWasResized = false;
uint  windowWidth      = 1280;
uint  windowHeight     = 720;

/// Set via querySwapchainSupport. Determines how many Frame structures we
/// allocate
uint  numSwapchainImages = 0;

enum MAX_ENTITIES = 1000;

/// Returns the aspect ratio of the current window
float aspectRatio() @nogc nothrow {
    return cast(float) globals.windowWidth / cast(float) globals.windowHeight;
}

float verticalFieldOfView = 20.0;
float nearPlane = 1.0;
float farPlane  = 10.0;

GLFWwindow *window;

VkClearValue[] clearValues = [
    { color        : { float32 : [0.0, 0.1, 0.2, 1.0] } },
    { depthStencil : { depth: 1.0, stencil: 0 } },
];



