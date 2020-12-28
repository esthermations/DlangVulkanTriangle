module glfw_callbacks;

import std.experimental.logger;

import glfw3.api;
import globals;
import game;

extern (C) nothrow @nogc:

void keyPressed(GLFWwindow *window, int key, int scancode, int keyAction, int) {

    auto gameAction = game.associatedAction(key);

    if (gameAction == GameAction.NO_ACTION) {
        import std.string : fromStringz;
        debug log("User pressed unbound key ", 
                  glfwGetKeyName(key, scancode).fromStringz);
        return;
    }

    // Otherwise, key is bound

    auto actionIsDesired = (keyAction == GLFW_PRESS || 
                            keyAction == GLFW_REPEAT);

    Frame *frame = cast(Frame *) glfwGetWindowUserPointer(Globals.window);
    frame.actionRequested[gameAction] = actionIsDesired;

    debug log("Action ", gameAction, " => ", actionIsDesired);
}

void framebufferResized(GLFWwindow *window, int width, int height) {
    Globals.windowHeight     = width;
    Globals.windowWidth      = height;
    Globals.windowWasResized = true;
}

