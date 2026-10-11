using System.Collections.Generic;
using System;

[TestClass]
public class JsonTest {
    [TestMethod]
    public void Test_Stringify_when_building_request() {
        JsonValue req = JsonValue.makeObject();
        req.put("type", JsonValue.of("ping"));
        req.put("n", JsonValue.of(42L));
        req.put("f", JsonValue.of(1.5));
        req.put("flag", JsonValue.of(true));
        req.put("nil", JsonValue.ofNull());
        JsonValue arr = JsonValue.makeArray();
        arr.add(JsonValue.of("a"));
        arr.add(JsonValue.of(2L));
        req.put("list", arr);
        Assert.AreEqual("{\"type\":\"ping\",\"n\":42,\"f\":1.5,\"flag\":true,\"nil\":null,\"list\":[\"a\",2]}", req.stringify());
    }

    [TestMethod]
    public void Test_Parse_when_reading_response() {
        JsonValue parsed = JsonValue.parse("{\"a\":1,\"b\":[true,null,\"x\"],\"c\":{\"d\":2.5}}");
        Assert.AreEqual(1L, parsed.intVal("a"));
        Assert.AreEqual(true, parsed.get("b").getAt(0).boolValue);
        Assert.AreEqual(true, parsed.get("b").getAt(1).isNull());
        Assert.AreEqual("x", parsed.get("b").getAt(2).stringValue);
        Assert.AreEqual(2.5, parsed.get("c").num("d"));
    }

    [TestMethod]
    public void Test_Stringify_when_escaping() {
        JsonValue s = JsonValue.of("line1\nline2 \"quoted\" \\ back");
        Assert.AreEqual("\"line1\\nline2 \\\"quoted\\\" \\\\ back\"", s.stringify());
    }
}