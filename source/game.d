module game;

import glfw3.api;
import gl3n.linalg;

import globals;

enum GameAction {
    NO_ACTION,
    MOVE_FORWARDS,
    MOVE_LEFT,
    MOVE_BACKWARDS,
    MOVE_RIGHT,
    PRINT_DEBUG_INFO,
    QUIT_GAME,
}

enum MOVEMENT_IMPULSE = 0.001;

struct GameState {
    static vec3 cameraPosition     = vec3(0.0, 1.0, -1.0);

    static vec3 playerPosition     = vec3(0.0, 0.0, 0.0); 
    static vec3 playerVelocity     = vec3(0.0, 0.0, 0.0);
    static vec3 playerAcceleration = vec3(0.0, 0.0, 0.0);
    static bool[GameAction.max + 1] actionRequested = [false];
}

/// Returns the GameAction associated with this keyboard key.
/// @key: should be a GLFW_KEY_* value.
GameAction associatedAction(int key) pure nothrow @nogc {
    switch (key) {
        case GLFW_KEY_W: return GameAction.MOVE_FORWARDS;
        case GLFW_KEY_A: return GameAction.MOVE_LEFT;
        case GLFW_KEY_S: return GameAction.MOVE_BACKWARDS;
        case GLFW_KEY_D: return GameAction.MOVE_RIGHT;
        case GLFW_KEY_P: return GameAction.PRINT_DEBUG_INFO;
        case GLFW_KEY_ESCAPE: return GameAction.QUIT_GAME;
        default: return GameAction.NO_ACTION;
    }
    assert(0);
}

void tickGameState() {

    // Update position based on velocity
    GameState.playerPosition += GameState.playerVelocity;
    GameState.playerVelocity += GameState.playerAcceleration;

    GameState.cameraPosition = 
        GameState.playerPosition + vec3(0, 5, 5);

    // Set acceleration based on player input
    GameState.playerAcceleration = vec3(0);

    if (GameState.actionRequested[GameAction.MOVE_FORWARDS]) {
        GameState.playerAcceleration.z += MOVEMENT_IMPULSE;
    }

    if (GameState.actionRequested[GameAction.MOVE_BACKWARDS]) {
        GameState.playerAcceleration.z -= MOVEMENT_IMPULSE;
    }

    if (GameState.actionRequested[GameAction.MOVE_RIGHT]) {
        GameState.playerAcceleration.x += MOVEMENT_IMPULSE;
    }

    if (GameState.actionRequested[GameAction.MOVE_LEFT]) {
        GameState.playerAcceleration.x -= MOVEMENT_IMPULSE;
    }

    if (GameState.actionRequested[GameAction.PRINT_DEBUG_INFO]) {
        import std.experimental.logger;
        debug log("Player position:     ", GameState.playerPosition);
        debug log("Player velocity:     ", GameState.playerVelocity);
        debug log("Player acceleration: ", GameState.playerAcceleration);
    }

    if (GameState.actionRequested[GameAction.QUIT_GAME]) {
        glfwSetWindowShouldClose(Globals.window, GLFW_TRUE);
    }
}
