module globals;

import glfw3.api;
import erupted;
import gl3n.linalg;

import core.time;

/// Global state pertaining to the program itself, not the game state.
struct Globals {
    static ulong currentFrame; /// Latest frame? This might be named better.

    static bool  windowWasResized = false;
    static uint  windowWidth      = 1280;
    static uint  windowHeight     = 720;

    /// Returns the aspect ratio of the current window
    static float aspectRatio() {
        return cast(float) windowWidth / cast(float) windowHeight;
    }

    static float verticalFieldOfView = 10.0;

    static MonoTime programT0;

    static GLFWwindow *window;

    static VkClearValue[] clearValues = [
        { color        : { float32 : [0.0, 0.0, 0.0, 1.0] } },
        { depthStencil : { depth: 1.0, stencil: 0 } },
    ];

}

