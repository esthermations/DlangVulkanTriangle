module game;

import std.typecons : Nullable;
import std.algorithm;
import std.exception : enforce;

import glfw3.api;
import gl3n.linalg; 
import erupted;
import globals;

import util;
import renderer;

enum GameAction {
    NO_ACTION,
    MOVE_FORWARDS,
    MOVE_BACKWARDS,
    MOVE_LEFT,
    MOVE_RIGHT,
    MOVE_UP,
    MOVE_DOWN,
    PRINT_DEBUG_INFO,
    QUIT_GAME,
}

enum MOVEMENT_IMPULSE = 0.001;

struct Frame {

    /// An index into the Vulkan swapchain corresponding to the image this frame
    /// will be rendered into.
    uint imageIndex; 

    mat4 projection; /// Projection uniform

    // Components

    Nullable!vec3         []position;
    Nullable!vec3         []velocity;
    Nullable!vec3         []acceleration;
    Nullable!vec3         []lookAtTarget;
    Nullable!bool         []controlledByPlayer;
    Nullable!float        []scale;
    Nullable!mat4         []modelMatrix;
    Nullable!mat4         []viewMatrix;
    Nullable!VertexBuffer []vertexBuffer;

    /// How many entities exist in this frame?
    auto numEntities() immutable {
        return position.length;
    }

    invariant {
        assert(position.length == position.length);
        assert(position.length == velocity.length);
        assert(position.length == acceleration.length);
        assert(position.length == lookAtTarget.length);
        assert(position.length == controlledByPlayer.length);
        assert(position.length == scale.length);
        assert(position.length == modelMatrix.length);
        assert(position.length == viewMatrix.length);
        assert(position.length == vertexBuffer.length);

        assert(scale.filter!(s => !s.isNull).all!(s => s >= 0.0));
    }

    // Entities

    uint createEntity()
        out (ret; this.position.length == ret + 1)
    {
        static uint nextEntityID = 0;

        immutable newLength = 1 + nextEntityID;

        this.position.length           = newLength;
        this.velocity.length           = newLength;
        this.acceleration.length       = newLength;
        this.scale.length              = newLength;
        this.viewMatrix.length         = newLength;
        this.lookAtTarget.length       = newLength;
        this.controlledByPlayer.length = newLength;
        this.modelMatrix.length        = newLength;
        this.vertexBuffer.length       = newLength;

        return nextEntityID++;
    }

    // Player input

    /// Has the player requested the specified action this frame?
    bool[GameAction.max + 1] actionRequested = [false];
}

Frame tick(Frame previousFrame, ref Renderer renderer) {
    import std.algorithm : map, fold, setIntersection, each;
    import std.experimental.logger;

    Frame thisFrame = {
        position           : previousFrame.position,
        velocity           : previousFrame.velocity,
        acceleration       : previousFrame.acceleration,
        lookAtTarget       : previousFrame.lookAtTarget,
        controlledByPlayer : previousFrame.controlledByPlayer,
        scale              : previousFrame.scale,
        modelMatrix        : previousFrame.modelMatrix,
        viewMatrix         : previousFrame.viewMatrix,
        vertexBuffer       : previousFrame.vertexBuffer,
        actionRequested    : [false],
    };

    thisFrame.imageIndex = renderer.acquireNextImageIndex(previousFrame.imageIndex);

    glfwSetWindowUserPointer(Globals.window, &thisFrame);
    glfwPollEvents();

    // Update velocities

    void updateVelocities() {
        auto velEnts = entitiesWithComponent(thisFrame.velocity);
        auto accEnts = entitiesWithComponent(thisFrame.acceleration);
        auto ents    = setIntersection(velEnts, accEnts);
        debug log(ents);
        foreach (e; ents) {
            thisFrame.velocity[e] += thisFrame.acceleration[e];
        }
    }

    // Update positions

    void updatePositions() {
        auto posEnts = entitiesWithComponent(thisFrame.position);
        auto velEnts = entitiesWithComponent(thisFrame.velocity);
        auto ents    = setIntersection(posEnts, velEnts);
        debug log(ents);
        foreach (e; ents) {
            thisFrame.position[e] += thisFrame.velocity[e];
        }
    }

    // Update model matrices

    void updateModelMatrices() {
        auto posEnts = entitiesWithComponent(thisFrame.position);
        auto sclEnts = entitiesWithComponent(thisFrame.scale);
        auto ents    = setIntersection(posEnts, sclEnts);
        debug log(ents);
        foreach (e; ents) {
            auto scale    = thisFrame.scale[e].get;
            auto position = thisFrame.position[e].get;
            thisFrame.modelMatrix[e] = mat4.identity.scale(scale, scale, scale)
                                                    .translate(position)
                                                    .transposed();
        }
    }

    // Update camera view matrices

    void updateViewMatrices() {
        auto lookAtEnts = entitiesWithComponent(thisFrame.lookAtTarget);
        auto posEnts    = entitiesWithComponent(thisFrame.position);
        auto cameras    = setIntersection(lookAtEnts, posEnts);
        debug log(cameras);
        foreach (e; cameras) {
            vec3 eyePos = thisFrame.position[e].get;
            vec3 targetPos = thisFrame.lookAtTarget[e].get;
            thisFrame.viewMatrix[e] = lookAt(eyePos, targetPos, vec3(0, 1.up, 0));
        }
    }

    // Issue render commands

    void renderVertexBuffers() {
        auto modelEnts = entitiesWithComponent(thisFrame.modelMatrix);
        auto vbufEnts  = entitiesWithComponent(thisFrame.vertexBuffer);
        auto renderableEntities = setIntersection(modelEnts, vbufEnts);
        debug log(renderableEntities);

        // NOTE: We're explicitly assuming here that only one entity (the
        // camera) will have a view matrix. Or at least, if there are multiple
        // view matrices, we're always using the first one.
        auto viewMatrixEnts = entitiesWithComponent(thisFrame.viewMatrix);
        auto viewMatrix = thisFrame.viewMatrix[viewMatrixEnts.front].get;
        debug log("Camera entity is: ", viewMatrixEnts.front);

        renderer.beginCommandsForFrame(thisFrame.imageIndex);

        foreach (e; renderableEntities) {
            Uniforms uniformData = {
                projection : thisFrame.projection,
                view       : viewMatrix,
                model      : thisFrame.modelMatrix[e].get,
            };

            renderer.setUniformDataForFrame(thisFrame.imageIndex, 
                                            uniformData);

            renderer.issueRenderCommands(thisFrame.imageIndex,
                                         thisFrame.vertexBuffer[e].get);
        }

        renderer.endCommandsForFrame(thisFrame.imageIndex);
    }

    // Set player's acceleration based on player input
    void updatePlayerAcceleration() {
        auto playerEntities = entitiesWithComponent(thisFrame.controlledByPlayer);
        auto accelEntities  = entitiesWithComponent(thisFrame.acceleration);
        auto ents = setIntersection(playerEntities, accelEntities);

        foreach (e; ents) {
            vec3 accel = vec3(0);

            if (thisFrame.actionRequested[GameAction.MOVE_FORWARDS])  { accel.z += MOVEMENT_IMPULSE.forwards;  }
            if (thisFrame.actionRequested[GameAction.MOVE_BACKWARDS]) { accel.z += MOVEMENT_IMPULSE.backwards; }
            if (thisFrame.actionRequested[GameAction.MOVE_RIGHT])     { accel.x += MOVEMENT_IMPULSE.right;     }
            if (thisFrame.actionRequested[GameAction.MOVE_LEFT])      { accel.x += MOVEMENT_IMPULSE.left;      }
            if (thisFrame.actionRequested[GameAction.MOVE_UP])        { accel.y += MOVEMENT_IMPULSE.up;        }
            if (thisFrame.actionRequested[GameAction.MOVE_DOWN])      { accel.y += MOVEMENT_IMPULSE.down;      }

            // Output
            thisFrame.acceleration[e] = accel;
        }
    }

    updateVelocities();
    updatePositions();
    updateModelMatrices();
    updateViewMatrices();
    updatePlayerAcceleration();
    renderVertexBuffers();

    if (thisFrame.actionRequested[GameAction.QUIT_GAME]) {
        glfwSetWindowShouldClose(Globals.window, GLFW_TRUE);
    }

    return thisFrame;
}

auto entitiesWithComponent(T)(T[] array) pure {
    import std.range     : iota;
    import std.algorithm : filter;
    auto indices = iota(0, array.length, 1); 
    auto ret = indices.filter!(i => !array[i].isNull);
    import std.experimental.logger;
    //debug log(" returning ", ret);
    return ret;
}

/// Returns the GameAction associated with this keyboard key.
/// @key: should be a GLFW_KEY_* value.
GameAction associatedAction(int key) pure nothrow @nogc {
    switch (key) {
        case GLFW_KEY_W            : return GameAction.MOVE_FORWARDS;
        case GLFW_KEY_A            : return GameAction.MOVE_LEFT;
        case GLFW_KEY_S            : return GameAction.MOVE_BACKWARDS;
        case GLFW_KEY_D            : return GameAction.MOVE_RIGHT;
        case GLFW_KEY_SPACE        : return GameAction.MOVE_UP;
        case GLFW_KEY_LEFT_CONTROL : return GameAction.MOVE_DOWN;
        case GLFW_KEY_P            : return GameAction.PRINT_DEBUG_INFO;
        case GLFW_KEY_ESCAPE       : return GameAction.QUIT_GAME;
        default                    : return GameAction.NO_ACTION;
    }
    assert(0);
}

