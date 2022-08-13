module globals;

import glfw3.api;
import erupted;

import core.time;
import std.concurrency : Tid, thisTid;

/**

    This module contains global state pertaining to the program itself, not the
    game state. It should be imported with a 'static import' command, so all its
    members must be prefixed with 'globals.' to be accessed.

**/

Tid mainThreadTid;

extern (C) nothrow @nogc:

uint  frameNumber      = 0;

bool  windowWasResized = false;
uint  windowWidth      = 1280;
uint  windowHeight     = 720;

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



