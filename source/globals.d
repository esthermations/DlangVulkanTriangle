module globals;

import erupted;

/// Global state. All member variables should be static.
struct Globals {
    static ulong currentFrame; /// Latest frame? This might be named better.
    static bool  framebufferWasResized = false;
    static uint  framebufferWidth = 800;
    static uint  framebufferHeight = 600;

    static VkClearValue clearColour = { 
        color : { float32 : [0.0, 0.0, 0.0, 1.0] },
    };
}
