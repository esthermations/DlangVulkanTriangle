module globals;

import glfw3.api;
import erupted;
import gl3n.linalg;

import core.time;

/// Global state pertaining to the program itself, not the game state.
ulong currentFrame; /// Latest frame? This might be named better.

bool  windowWasResized = false;
uint  windowWidth      = 1280;
uint  windowHeight     = 720;

/// Returns the aspect ratio of the current window
float aspectRatio() {
    return cast(float) windowWidth / cast(float) windowHeight;
}

float verticalFieldOfView = 10.0;
float nearPlane = 1.0;
float farPlane  = 10.0;

MonoTime programT0;

GLFWwindow *window;

VkClearValue[] clearValues = [
    { color        : { float32 : [0.0, 0.0, 0.0, 1.0] } },
    { depthStencil : { depth: 1.0, stencil: 0 } },
];



