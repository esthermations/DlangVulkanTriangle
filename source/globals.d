module globals;

import glfw3.api;
import erupted;
import gl3n.linalg;

import core.time;

/// Global state. All member variables should be static.
struct Globals {
    static ulong currentFrame; /// Latest frame? This might be named better.

    static bool  framebufferWasResized = false;
    static uint  framebufferWidth = 1280;
    static uint  framebufferHeight = 720;

    static float aspectRatio() {
        return cast(float) framebufferWidth / cast(float) framebufferHeight;
    }

    static float verticalFieldOfView = 10.0;

    static MonoTime programT0;
    static Duration lastFrameDuration;

    static immutable Duration frameDeadline = 2.msecs;

    static GLFWwindow *window;

    static VkClearValue[] clearValues = [
        { color        : { float32 : [0.0, 0.0, 0.0, 1.0] } },
        { depthStencil : { depth: 1.0, stencil: 0 } },
    ];

    static Uniforms[] uniforms;
}

struct Uniforms {
    mat4 model;
    mat4 view;
    mat4 projection;
}

struct Vertex {
    vec3 position;
    vec3 normal;

    static VkVertexInputBindingDescription getBindingDescription() {
        VkVertexInputBindingDescription ret = {
            binding   : 0,
            stride    : Vertex.sizeof,
            inputRate : VK_VERTEX_INPUT_RATE_VERTEX,
        };
        return ret;
    }

    static VkVertexInputAttributeDescription[2] getAttributeDescription() {
        VkVertexInputAttributeDescription[2] ret = [
            {
                binding : 0,
                location : 0,
                format   : VK_FORMAT_R32G32B32_SFLOAT,
                offset   : Vertex.position.offsetof,
            },
            {
                binding  : 0,
                location : 1,
                format   : VK_FORMAT_R32G32B32_SFLOAT,
                offset   : Vertex.normal.offsetof,
            }
        ];
        return ret;
    }
}

