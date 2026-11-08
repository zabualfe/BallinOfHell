describe("TableUtil", function()
	local TableUtil = load("ReplicatedStorage/Utilities/TableUtil")

	it("deep copies without sharing tables", function()
		local source = { a = { b = { 1, 2 } }, c = 3 }
		local copy = TableUtil.DeepCopy(source)
		expect(copy):equal(source)
		copy.a.b[1] = 99
		expect(source.a.b[1]):equal(1)
		expect(TableUtil.DeepCopy(5)):equal(5)
		expect(TableUtil.DeepCopy(nil)):equal(nil)
	end)

	it("sets nested paths and creates missing tables", function()
		local root = { settings = { sound = true } }
		expect(TableUtil.SetPath(root, "settings.sound", false)):truthy()
		expect(root.settings.sound):equal(false)
		expect(TableUtil.SetPath(root, "season.claimedFree.3", true)):truthy()
		expect(root.season.claimedFree["3"]):equal(true)
		expect(TableUtil.SetPath(root, "coins", 7)):truthy()
		expect(root.coins):equal(7)
	end)

	it("treats numeric path segments as array indices", function()
		local root = { challenges = { daily = { { progress = 0 } } }, season = { claimedFree = {} } }
		expect(TableUtil.SetPath(root, "challenges.daily.1.progress", 3)):truthy()
		expect(root.challenges.daily[1].progress):equal(3)
		expect(root.challenges.daily["1"]):equal(nil)
		expect(TableUtil.GetPath(root, "challenges.daily.1.progress")):equal(3)
		expect(TableUtil.SetPath(root, "challenges.daily.2", { progress = 1 })):truthy()
		expect(#root.challenges.daily):equal(2)
		root.season.claimedFree["5"] = false
		expect(TableUtil.SetPath(root, "season.claimedFree.5", true)):truthy()
		expect(root.season.claimedFree["5"]):equal(true)
	end)

	it("refuses blocked and malformed paths without mutating", function()
		local root = { coins = 5 }
		expect(TableUtil.SetPath(root, "coins.x", 1)):falsy()
		expect(TableUtil.SetPath(root, "", 1)):falsy()
		expect(TableUtil.SetPath(root, "a..b", 1)):falsy()
		expect(TableUtil.SetPath(root, 5, 1)):falsy()
		expect(root):equal({ coins = 5 })
	end)

	it("gets nested values", function()
		local root = { a = { b = 4 } }
		expect(TableUtil.GetPath(root, "a.b")):equal(4)
		expect(TableUtil.GetPath(root, "a.x.y")):equal(nil)
		expect(TableUtil.GetPath(root, "a.b.c")):equal(nil)
	end)

	it("compares deeply", function()
		expect(TableUtil.DeepEqual({ a = { 1 } }, { a = { 1 } })):truthy()
		expect(TableUtil.DeepEqual({ a = 1 }, { a = 1, b = 2 })):falsy()
		expect(TableUtil.DeepEqual({ a = 1, b = 2 }, { a = 1 })):falsy()
	end)
end)
