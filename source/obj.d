module obj;

/**
    Parser for Wavefront OBJ files.
*/

import gl3n.linalg;

struct MtlData {
    string name;
    vec3   ambientLight;
    vec3   diffuseLight;
    vec3   specularLight;
    ulong  firstIndex;
    ulong  numIndices;
}

struct ObjData {
    vec3[]    vertices;
    vec3[]    normals;
    vec2[]    texcoords;
    MtlData[] materials;
}

ObjData parseObj(string objFilePath) {
    import std.stdio  : File;
    File objFile = File(objFilePath);

    ObjData ret;

    import std.string    : strip, split, startsWith;
    import std.algorithm : map;

    vec3 stringsToVec3(string[] splitString) 
        in (splitString.length == 3)
    {
        import std.conv : to;
        vec3 ret;
        ret.x = splitString[0].to!float;
        ret.y = splitString[1].to!float;
        ret.z = splitString[2].to!float;
        return ret;
    }

    vec2 stringsToVec2(string[] splitString) 
        in (splitString.length == 2)
    {
        import std.conv : to;
        vec2 ret;
        ret.x = splitString[0].to!float;
        ret.y = splitString[1].to!float;
        return ret;
    }



    foreach (splitLine; objFile.byLineCopy.map!(strip)
                                          .map!(s => s.split(" "))) 
    {

        if (splitLine.length == 0 || splitLine[0].startsWith("#")) {
            continue;
        }

        switch (splitLine[0]) {
            case "v" : ret.vertices  ~= stringsToVec3(splitLine[1 .. $]);
            case "vn": ret.normals   ~= stringsToVec3(splitLine[1 .. $]);
            case "vt": ret.texcoords ~= stringsToVec2(splitLine[1 .. $]);
            case "f":  
            case "mtllib":
            case "usemtl":
            case "g":
            case "o":
            case "s":
            default: assert(0);
        }

    }

    return ret;
}

