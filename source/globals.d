module globals;

import erupted;
import gl3n.linalg;

import core.time;

/// Global state. All member variables should be static.
struct Globals {
    static ulong currentFrame; /// Latest frame? This might be named better.

    static bool  framebufferWasResized = false;
    static uint  framebufferWidth = 800;
    static uint  framebufferHeight = 600;

    static float fieldOfView = 90.0;

    static MonoTime programT0;

    static VkClearValue clearColour = { 
        color : { float32 : [0.0, 0.0, 0.0, 1.0] },
    };

    static const Vertex[] vertices = [ 
        { position: vec2( 0.0, -0.5), colour: vec3(1.0, 0.0, 0.0) },
        { position: vec2( 0.5,  0.5), colour: vec3(0.0, 1.0, 0.0) },
        { position: vec2(-0.5,  0.5), colour: vec3(0.0, 0.0, 1.0) },
    ];

    static Uniforms[] uniforms;
}

struct Uniforms {
    mat4 model;
    mat4 view;
    mat4 projection;
}

struct Vertex {
    vec2 position;
    vec3 colour;

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
                format   : VK_FORMAT_R32G32_SFLOAT,
                offset   : Vertex.position.offsetof,
            },
            {
                binding  : 0,
                location : 1,
                format   : VK_FORMAT_R32G32B32_SFLOAT,
                offset   : Vertex.colour.offsetof,
            }
        ];
        return ret;
    }
}

