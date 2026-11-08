describe("test loader", function()
	it("resolves siblings through script.Parent and services", function()
		local Signal = load("ReplicatedStorage/Utilities/Signal")
		local signal = Signal.new()
		local got
		signal:Connect(function(value)
			got = value
		end)
		signal:Fire(5)
		expect(got):equal(5)
		expect(game:GetService("ReplicatedStorage").Utilities.Weighted.ClassName):equal("ModuleScript")
	end)

	it("colours RichText from a Color3", function()
		local RichText = load("ReplicatedStorage/Utilities/RichText")
		expect(RichText.Color("x", Color3.fromRGB(255, 0, 0)):lower()):equal('<font color="#ff0000">x</font>')
		expect(RichText.Bold("x")):equal("<b>x</b>")
	end)
end)
