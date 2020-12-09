module game;

import glfw3.api;
import gl3n.linalg; 
import globals;
import util;

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

struct Game {

    static uint createEntity();

    import std.typecons : Nullable;

    static uint playerEntity;

    static Nullable!vec3[] position;
    static Nullable!vec3[] velocity;
    static Nullable!vec3[] acceleration;

    invariant(position.length == velocity.length);
    invariant(position.length == acceleration.length);

    static uint createEntity()
        out (ret; position.length == ret + 1)
    {
        static uint nextEntityID = 0;

        Game.position.length     = 1 + nextEntityID;
        Game.velocity.length     = 1 + nextEntityID;
        Game.acceleration.length = 1 + nextEntityID;

        return nextEntityID++;
    }

    /// Has the player requested the specified action this frame?
    static bool[GameAction.max + 1] actionRequested = [false];

    static void tick() {

        import std.algorithm : map, fold, setIntersection, each;
        import std.experimental.logger;

        // set of all entities that have acceleration and velocity

        //auto ents = query(Game.velocity, Game.acceleration, Game.fleebleBoo, Game.nintendo64);

        {
            auto velEnts = entitiesWithComponent(Game.velocity);
            auto accEnts = entitiesWithComponent(Game.acceleration);
            auto ents = setIntersection(velEnts, accEnts);
            debug log(ents);
            foreach (e; ents) {
                Game.velocity[e] += Game.acceleration[e];
            }
        }

        {
            auto posEnts = entitiesWithComponent(Game.position);
            auto velEnts = entitiesWithComponent(Game.velocity);
            auto ents = setIntersection(posEnts, velEnts);
            debug log(ents);
            foreach (e; ents) {
                Game.position[e] += Game.velocity[e];
            }
        }

        // Set player's acceleration based on player input
        Game.acceleration[playerEntity] = vec3(0);

        if (Game.actionRequested[GameAction.MOVE_FORWARDS]) {
            Game.acceleration[playerEntity].get.z += MOVEMENT_IMPULSE.forwards;
        }

        if (Game.actionRequested[GameAction.MOVE_BACKWARDS]) {
            Game.acceleration[playerEntity].get.z += MOVEMENT_IMPULSE.backwards;
        }

        if (Game.actionRequested[GameAction.MOVE_RIGHT]) {
            Game.acceleration[playerEntity].get.x += MOVEMENT_IMPULSE.right;
        }

        if (Game.actionRequested[GameAction.MOVE_LEFT]) {
            Game.acceleration[playerEntity].get.x += MOVEMENT_IMPULSE.left;
        }

        if (Game.actionRequested[GameAction.MOVE_UP]) {
            Game.acceleration[playerEntity].get.y += MOVEMENT_IMPULSE.up;
        }

        if (Game.actionRequested[GameAction.MOVE_DOWN]) {
            Game.acceleration[playerEntity].get.y += MOVEMENT_IMPULSE.down;
        }

        if (Game.actionRequested[GameAction.PRINT_DEBUG_INFO]) {
            import std.experimental.logger;
            debug log("Player position:     ", Game.position[playerEntity].get);
            debug log("Player velocity:     ", Game.velocity[playerEntity].get);
            debug log("Player acceleration: ", Game.acceleration[playerEntity].get);
        }

        if (Game.actionRequested[GameAction.QUIT_GAME]) {
            glfwSetWindowShouldClose(Globals.window, GLFW_TRUE);
        }
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
