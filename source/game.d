module game;

import std.algorithm;
import std.conv        : to;
import std.typecons    : Nullable;
import std.exception   : enforce;
import std.parallelism : parallel;
import std.experimental.logger;

import glfw3.api;
import gl3n.linalg;
import erupted;
static import globals;

import util;
import renderer_interface;
import shader_abi;

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


alias Entity = size_t;


// Per-entity component data
struct EcsState {

    Nullable!vec3         [globals.MAX_ENTITIES]position;
    Nullable!vec3         [globals.MAX_ENTITIES]velocity;
    Nullable!vec3         [globals.MAX_ENTITIES]acceleration;
    Nullable!Entity       [globals.MAX_ENTITIES]lookAtTargetEntity;
    Nullable!bool         [globals.MAX_ENTITIES]controlledByPlayer;
    Nullable!float        [globals.MAX_ENTITIES]scale;
    Nullable!mat4         [globals.MAX_ENTITIES]modelMatrix;
    Nullable!mat4         [globals.MAX_ENTITIES]viewMatrix;
    Nullable!(Renderer.Buffer) [globals.MAX_ENTITIES]vertexBuffer;

    // Entities

    Entity nextEntityID = 0;

    Entity createEntity()
        in  (nextEntityID != globals.MAX_ENTITIES)
        out (ret; nextEntityID == (ret + 1))
    {
        return nextEntityID++;
    }

    // Systems

    void updateVelocities() {
        auto velEnts = entitiesWithComponent(this.velocity);
        auto accEnts = entitiesWithComponent(this.acceleration);
        auto ents    = setIntersection(velEnts, accEnts);
        debug(ecs) log(ents);
        foreach (e; ents) {
            this.velocity[e].get() += this.acceleration[e].get();
        }
    }


    void updatePositions() {
        auto posEnts = entitiesWithComponent(this.position);
        auto velEnts = entitiesWithComponent(this.velocity);
        auto ents    = setIntersection(posEnts, velEnts);
        debug(ecs) log(ents);
        foreach (e; ents.parallel) {
            this.position[e].get() += this.velocity[e].get();
        }
    }


    void updateModelMatrices() {
        auto posEnts = entitiesWithComponent(this.position);
        auto sclEnts = entitiesWithComponent(this.scale);
        auto ents    = setIntersection(posEnts, sclEnts);
        debug(ecs) log(ents);

        foreach (e; ents.parallel) {
            auto scale    = this.scale[e].get;
            auto position = this.position[e].get;
            this.modelMatrix[e] = mat4.identity.scale(scale, scale, scale)
                                                    .translate(position)
                                                    .transposed();
        }
    }


    // Update camera view matrices
    void updateViewMatrices() {
        auto lookAtEnts = entitiesWithComponent(this.lookAtTargetEntity);
        auto posEnts    = entitiesWithComponent(this.position);
        auto cameras    = setIntersection(lookAtEnts, posEnts);
        debug(ecs) log(cameras);
        foreach (e; cameras) {
            vec3 eyePos = this.position[e].get();
            Entity targetEntity = this.lookAtTargetEntity[e].get();
            vec3 targetPos    = this.position[targetEntity].get();
            this.viewMatrix[e] = lookAt(eyePos, targetPos, vec3(0, 1.up, 0));
        }
    }


    /// Prepare updated uniform data
    Uniforms updateUniforms(mat4 projection) {
        // NOTE: We're explicitly assuming here that only one entity (the
        // camera) will have a view matrix. Or at least, if there are multiple
        // view matrices, we're always using the first one.
        auto viewMatrixEnts = entitiesWithComponent(this.viewMatrix);
        debug log("viewMatrixEnts.length = " ~ viewMatrixEnts.length.to!string);
        assert(viewMatrixEnts.length == 1);

        import std.range : front;
        auto viewMatrix = this.viewMatrix[viewMatrixEnts.front].get;
        debug(ecs) log("Camera entity is: ", viewMatrixEnts.front);

        Uniforms uniformData = {
            projection : projection,
            view       : viewMatrix,
            // Models is not set yet
        };

        auto modelMatrixEnts = entitiesWithComponent(this.modelMatrix);

        uint i = 0;
        foreach (e; modelMatrixEnts) {
            uniformData.models[i++] = this.modelMatrix[e].get();
        }

        return uniformData;
    }


    /// Render vertex buffers
    void renderEntities(Renderer renderer, Uniforms ubo, FrameId fid) {
        /*
            TODO: Entity data sorting per vertex buffer, see comment in
            shader.vert.
        */

        auto modelEnts = entitiesWithComponent(this.modelMatrix);
        auto vbufEnts  = entitiesWithComponent(this.vertexBuffer);
        auto renderableEntities = setIntersection(modelEnts, vbufEnts);
        debug(ecs) log(renderableEntities);

        renderer.beginCommandsForFrame(fid, cast(ubyte[]) ubo);

        uint[Renderer.Buffer] counts;

        foreach (e; vbufEnts) {
            auto vbuf = this.vertexBuffer[e].get();
            counts[vbuf]++;
        }

        foreach (vbuf, instanceCount; counts) {
            renderer.drawVertexBuffer(fid, vbuf, instanceCount);
        }

        renderer.endCommandsForFrame(fid);
    }


    // Set player's acceleration based on player input
    void updatePlayerAcceleration(bool[] actionRequested)
        in (actionRequested.length == GameAction.max + 1)
    {
        auto playerEntities = entitiesWithComponent(this.controlledByPlayer);
        auto accelEntities  = entitiesWithComponent(this.acceleration);
        auto ents = setIntersection(playerEntities, accelEntities);

        foreach (e; ents) {
            vec3 accel = vec3(0);

            import globals : MOVEMENT_IMPULSE;

            if (actionRequested[GameAction.MOVE_FORWARDS])  { accel.z += MOVEMENT_IMPULSE.forwards;  }
            if (actionRequested[GameAction.MOVE_BACKWARDS]) { accel.z += MOVEMENT_IMPULSE.backwards; }
            if (actionRequested[GameAction.MOVE_RIGHT])     { accel.x += MOVEMENT_IMPULSE.right;     }
            if (actionRequested[GameAction.MOVE_LEFT])      { accel.x += MOVEMENT_IMPULSE.left;      }
            if (actionRequested[GameAction.MOVE_UP])        { accel.y += MOVEMENT_IMPULSE.up;        }
            if (actionRequested[GameAction.MOVE_DOWN])      { accel.y += MOVEMENT_IMPULSE.down;      }

            // Output
            this.acceleration[e] = accel;
        }
    }
}


struct Frame {
    FrameId fid;

    import shader_abi : Uniforms;
    Uniforms uniformData;

    mat4 projection; /// Projection uniform

    EcsState ecs;

    /// Has the player requested the specified action this frame?
    bool[GameAction.max + 1] actionRequested = [false];
}


Frame tick(Frame *previousFrame, Renderer renderer) {
    import std.algorithm : map, fold, setIntersection, each;

    Frame thisFrame;
    //thisFrame.setNumEntities(previousFrame.numEntities());

    thisFrame.ecs = previousFrame.ecs;
    thisFrame.actionRequested[] = false;

    thisFrame.fid = renderer.acquireNextFrameId();

    glfwSetWindowUserPointer(globals.window, &thisFrame);

    // Poll GLFW events. This may result in the frame's state being modified
    // through the user pointer we just set, by the functions in
    // glfw_callbacks.d.
    glfwPollEvents();

    /*
        Run systems
    */

    thisFrame.ecs.updateVelocities();
    thisFrame.ecs.updatePositions();
    thisFrame.ecs.updateModelMatrices();
    thisFrame.ecs.updateViewMatrices();
    thisFrame.ecs.updatePlayerAcceleration(thisFrame.actionRequested);
    Uniforms ubo = thisFrame.ecs.updateUniforms(thisFrame.projection);
    thisFrame.ecs.renderEntities(renderer, ubo, thisFrame.fid);

    if (thisFrame.actionRequested[GameAction.QUIT_GAME]) {
        glfwSetWindowShouldClose(globals.window, GLFW_TRUE);
    }

    return thisFrame;
}


/**
    Returns the indices into the given array for which the element is not null.
*/
Entity[] entitiesWithComponent(T)(T[] array) pure {
    import std.range     : iota;
    import std.algorithm : filter, map;

    auto indices = iota(0, array.length, 1);
    auto ents = indices.filter!(i => array[i].isNull);

    Entity[] ret;
    ret.length = 1;

    foreach (e; ents) {
        ret[$-1] = e;
        ret.length += 1;
    }

    ret.length -= 1;

    debug(ecs) {
        import std.experimental.logger : log;
        logf("%s returning %s", __FUNCTION__, ret);
    }

    return ret;
}


/// Unfortunately this isn't provided by GLFW and this is literally how they do
/// their error checking internally.
bool isValidGlfwKey(int key) pure nothrow @nogc {
    return key >= GLFW_KEY_SPACE && key <= GLFW_KEY_LAST;
}


/// Returns the GameAction associated with this keyboard key.
/// @key: should be a GLFW_KEY_* value.
GameAction associatedAction(int key) pure nothrow @nogc
    in (isValidGlfwKey(key))
{
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

