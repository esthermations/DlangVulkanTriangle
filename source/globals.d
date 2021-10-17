module globals;

import glfw3.api;
import erupted;
import gl3n.linalg;

import core.time;

/**

    This module contains global state pertaining to the program itself, not the
    game state. It should be imported with a 'static import' command, so all
    its members must be prefixed with 'globals.' to be accessed.

**/
extern (C) nothrow @nogc:


/// Set via querySwapchainSupport. Determines how many Frame structures we
/// allocate.
uint maxFramesInFlight = 0;


/// The maximum number of entities the ECS will allow you to create.
enum MAX_ENTITIES = 10;


/// Space is allocated in the uniform buffer for this many model uniforms. It
/// should possibly just be set to = MAX_ENTITIES.
enum MAX_MODEL_UNIFORMS = 1000;


/// The value that is added to the player's acceleration when they press a
/// movement button.
enum MOVEMENT_IMPULSE = 0.001;



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



