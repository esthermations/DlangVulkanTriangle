module shader_abi;

import gl3n.linalg;
import game :  Entity;
static import globals;

/// Data layout for vertices. Should be reflected in shader.vert.
struct Vertex {
    vec3 position; /// Model-space position of this vertex
    vec3 normal;   /// Vertex normal vector
}


/// Data layout for uniforms. Should be reflected in shader.vert.
struct Uniforms {
    mat4[globals.MAX_MODEL_UNIFORMS] models;
    mat4                             view;
    mat4                             projection;
}
