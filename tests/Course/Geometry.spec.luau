describe("SegmentChain", function()
	local SegmentChain = load("ServerScriptService/Script/CourseService/SegmentChain")

	local function near(a, b)
		expect((a.Position - b.Position).Magnitude):near(0, 1e-3)
		expect((a.LookVector - b.LookVector).Magnitude):near(0, 1e-3)
		expect((a.UpVector - b.UpVector).Magnitude):near(0, 1e-3)
	end

	it("puts the end of segment n on the start of segment n+1, through turns and climbs", function()
		-- Pivot-space start/end of three fake segments: straight, left turn with a climb, right turn with a drop.
		local segments = {
			{ Start = CFrame.new(0, 0, 10), End = CFrame.new(0, 0, -40) },
			{ Start = CFrame.new(2, 0, 20), End = CFrame.new(-30, 15, -10) * CFrame.Angles(0, math.rad(90), 0) },
			{ Start = CFrame.new(0, 1, 5), End = CFrame.new(25, -10, -5) * CFrame.Angles(0, math.rad(-90), 0) },
		}
		local anchor = CFrame.new(5, 100, -3) * CFrame.Angles(0, math.rad(33), 0)
		local previousEnd
		for _, segment in segments do
			local pivot, endCF = SegmentChain.Place(anchor, segment.Start, segment.End)
			near(pivot * segment.Start, anchor)
			if previousEnd then
				near(pivot * segment.Start, previousEnd)
			end
			previousEnd, anchor = endCF, endCF
		end
	end)

	it("round-trips offsets taken from a world-space segment", function()
		local pivot = CFrame.new(40, 5, -9) * CFrame.Angles(0.2, 1.1, 0)
		local startWorld = pivot * CFrame.new(1, 2, 3)
		local endWorld = pivot * CFrame.new(-4, 8, 60)
		local startRel, endRel = SegmentChain.GetOffsets(pivot, startWorld, endWorld)
		local newPivot, newEnd = SegmentChain.Place(startWorld, startRel, endRel)
		near(newPivot, pivot)
		near(newEnd, endWorld)
	end)
end)

describe("FallZones", function()
	local FallZones = load("ServerScriptService/Script/CourseService/FallZones")

	local function box(center, size, yaw)
		return CFrame.new(center) * CFrame.Angles(0, math.rad(yaw or 0), 0), size
	end

	it("detects a fall under a segment that turns", function()
		-- A 20x10x100 box turned 90 degrees: long along world X.
		local cf, size = box(Vector3.new(0, 50, 0), Vector3.new(20, 10, 100), 90)
		local zones = { FallZones.FromBox(cf, size, 2, 10) }
		expect(FallZones.Find(zones, Vector3.new(40, 30, 0), nil)):equal(1)
		expect(FallZones.Find(zones, Vector3.new(0, 30, 40), nil)):equal(nil)
	end)

	it("ignores positions above the trigger depth", function()
		local cf, size = box(Vector3.new(0, 50, 0), Vector3.new(20, 10, 100))
		local zones = { FallZones.FromBox(cf, size, 2, 10) }
		expect(FallZones.Find(zones, Vector3.new(0, 46, 0), nil)):equal(nil)
		expect(FallZones.Find(zones, Vector3.new(0, 34, 0), nil)):equal(1)
	end)

	it("falls back to the global floor and the nearest segment", function()
		local cfA, sizeA = box(Vector3.new(0, 50, 0), Vector3.new(20, 10, 20))
		local cfB, sizeB = box(Vector3.new(500, 50, 0), Vector3.new(20, 10, 20))
		local zones = { FallZones.FromBox(cfA, sizeA, 2, 10), FallZones.FromBox(cfB, sizeB, 2, 10) }
		local floorY = FallZones.GetFloorY(zones, 200)
		expect(floorY):near(-155, 1e-6)
		expect(FallZones.Find(zones, Vector3.new(400, -160, 0), floorY)):equal(2)
		expect(FallZones.Find(zones, Vector3.new(400, 0, 0), floorY)):equal(nil)
	end)

	it("handles an empty course", function()
		expect(FallZones.Find({}, Vector3.new(0, -1000, 0), -500)):equal(nil)
	end)
end)
