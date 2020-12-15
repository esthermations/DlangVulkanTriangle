module game;

import glfw3.api;
import gl3n.linalg; 
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
    import std.typecons : Nullable;

    // Renderer state

    Uniforms uniforms;

    // Components

    Nullable!vec3[]  position;
    Nullable!vec3[]  velocity;
    Nullable!vec3[]  acceleration;
    Nullable!float[] scale;
    Nullable!mat4[]  viewMatrix;

    invariant(position.length == velocity.length);
    invariant(position.length == acceleration.length);
    invariant(position.length == scale.length);
    invariant(position.length == viewMatrix.length);

    // Entities

    uint playerEntity;

    uint createEntity()
        out (ret; this.position.length == ret + 1)
    {
        static uint nextEntityID = 0;

        this.position.length     = 1 + nextEntityID;
        this.velocity.length     = 1 + nextEntityID;
        this.acceleration.length = 1 + nextEntityID;
        this.scale.length        = 1 + nextEntityID;
        this.viewMatrix.length   = 1 + nextEntityID;

        return nextEntityID++;
    }

    // Player input

    /// Has the player requested the specified action this frame?
    bool[GameAction.max + 1] actionRequested = [false];
}

Frame tick(Frame previousFrame) pure {
    import std.algorithm : map, fold, setIntersection, each;
    import std.experimental.logger;

    Frame nextFrame = {
        playerEntity    : previousFrame.playerEntity,
        position        : previousFrame.position,
        velocity        : previousFrame.velocity,
        acceleration    : previousFrame.acceleration,
        actionRequested : [false],
    };

    glfwSetWindowUserPointer(Globals.window, &nextFrame);

    // set of all entities that have acceleration and velocity

    //auto ents = query(Game.velocity, Game.acceleration, Game.fleebleBoo, Game.nintendo64);

    {
        auto velEnts = entitiesWithComponent(previousFrame.velocity);
        auto accEnts = entitiesWithComponent(previousFrame.acceleration);
        auto ents    = setIntersection(velEnts, accEnts);
        debug log("updateVelocity: ", ents);
        foreach (e; ents) {
            nextFrame.velocity[e] += previousFrame.acceleration[e];
        }
    }

    {
        auto posEnts = entitiesWithComponent(previousFrame.position);
        auto velEnts = entitiesWithComponent(previousFrame.velocity);
        auto ents    = setIntersection(posEnts, velEnts);
        debug log("updatePosition: ", ents);
        foreach (e; ents) {
            nextFrame.position[e] += previousFrame.velocity[e];
        }
    }

    {
        auto posEnts = entitiesWithComponent(previousFrame.position);
        auto sclEnts = entitiesWithComponent(previousFrame.scale);
        auto ents    = setIntersection(posEnts, sclEnts);
        debug log("updateViewMatrix: ", ents);
        foreach (e; ents) {
            auto scale    = previousFrame.scale[e];
            auto position = previousFrame.position[e];
            nextFrame.viewMatrix[e] = mat4.identity.scale(scale, scale, scale)
                                                   .translate(position)
                                                   .transposed();
        }
    }

    glfwPollEvents();

    // Set player's acceleration based on player input
    nextFrame.acceleration[playerEntity] = vec3(0);

    if (nextFrame.actionRequested[nextFrameAction.MOVE_FORWARDS]) {
        nextFrame.acceleration[playerEntity].get.z += MOVEMENT_IMPULSE.forwards;
    }

    if (nextFrame.actionRequested[nextFrameAction.MOVE_BACKWARDS]) {
        nextFrame.acceleration[playerEntity].get.z += MOVEMENT_IMPULSE.backwards;
    }

    if (nextFrame.actionRequested[nextFrameAction.MOVE_RIGHT]) {
        nextFrame.acceleration[playerEntity].get.x += MOVEMENT_IMPULSE.right;
    }

    if (nextFrame.actionRequested[nextFrameAction.MOVE_LEFT]) {
        nextFrame.acceleration[playerEntity].get.x += MOVEMENT_IMPULSE.left;
    }

    if (nextFrame.actionRequested[nextFrameAction.MOVE_UP]) {
        nextFrame.acceleration[playerEntity].get.y += MOVEMENT_IMPULSE.up;
    }

    if (nextFrame.actionRequested[nextFrameAction.MOVE_DOWN]) {
        nextFrame.acceleration[playerEntity].get.y += MOVEMENT_IMPULSE.down;
    }

    if (nextFrame.actionRequested[nextFrameAction.PRINT_DEBUG_INFO]) {
        import std.experimental.logger;
        debug log("Player position:     ", nextFrame.position[playerEntity].get);
        debug log("Player velocity:     ", nextFrame.velocity[playerEntity].get);
        debug log("Player acceleration: ", nextFrame.acceleration[playerEntity].get);
    }

    if (nextFrame.actionRequested[nextFrameAction.QUIT_GAME]) {
        glfwSetWindowShouldClose(Globals.window, GLFW_TRUE);
    }
}

auto entitiesWithComponent(T)(T[] array) pure {
    import std.range     : iota;
    import std.algorithm : filter;
    auto indices = iota(0, array.length, 1); 
    auto ret = indices.filter!(i => !array[i].isNull);
    import std.experimental.logger;
    debug log(" returning ", ret);
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

