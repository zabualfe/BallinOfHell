describe("FlagService Resolve", function()
	local Resolve = load("ServerScriptService/Script/FlagService/Resolve")

	local flag = { Key = "X", Default = 5 }
	local test = { Key = "T", Default = "A", Variants = { A = 50, B = 50 } }

	it("falls back to the default when remote config never loaded", function()
		expect(Resolve.Value(flag, nil)):equal(5)
	end)

	it("takes a remote value of the right type", function()
		expect(Resolve.Value(flag, 9)):equal(9)
	end)

	it("ignores a remote value of the wrong type", function()
		expect(Resolve.Value(flag, "nine")):equal(5)
	end)

	it("ignores remote when disabled", function()
		expect(Resolve.Value({ Key = "X", Default = 5, Disabled = true }, 9)):equal(5)
	end)

	it("rejects bad definitions", function()
		expect(Resolve.Validate({ Default = 1 })):falsy()
		expect(Resolve.Validate({ Key = "K" })):falsy()
		expect(Resolve.Validate({ Key = "K", Default = "Z", Variants = { A = 1 } })):falsy()
		expect(Resolve.Validate(test)):truthy()
	end)

	it("backs off exponentially up to the cap", function()
		expect(Resolve.Backoff(1, 2, 60)):equal(2)
		expect(Resolve.Backoff(3, 2, 60)):equal(8)
		expect(Resolve.Backoff(10, 2, 60)):equal(60)
	end)

	it("buckets deterministically per user and test", function()
		expect(Resolve.Bucket(12345, "T")):equal(Resolve.Bucket(12345, "T"))
		expect(Resolve.Bucket(12345, "T") ~= Resolve.Bucket(12345, "U")):truthy()
		local bucket = Resolve.Bucket(98765, "T")
		expect(bucket >= 0 and bucket < 1):truthy()
	end)

	it("splits users close to the declared weights", function()
		local counts = { A = 0, B = 0 }
		local total = 10000
		for userId = 1, total do
			counts[Resolve.Variant(test, 1000000 + userId, nil)] += 1
		end
		expect(counts.A / total):near(0.5, 0.03)
		expect(counts.B / total):near(0.5, 0.03)
	end)

	it("respects uneven weights", function()
		local uneven = { Key = "U", Default = "A", Variants = { A = 90, B = 10 } }
		local b = 0
		local total = 10000
		for userId = 1, total do
			if Resolve.Variant(uneven, userId, nil) == "B" then
				b += 1
			end
		end
		expect(b / total):near(0.1, 0.03)
	end)

	it("returns the default variant when disabled and honours a forced one", function()
		expect(Resolve.Variant({ Key = "T", Default = "A", Disabled = true, Variants = { A = 1, B = 1 } }, 7, "B")):equal(
			"A"
		)
		expect(Resolve.Variant(test, 7, "B")):equal("B")
		expect(Resolve.Variant(test, 7, "Z") == "A" or Resolve.Variant(test, 7, "Z") == "B"):truthy()
	end)
end)
