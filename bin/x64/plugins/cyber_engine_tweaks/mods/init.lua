-- The data structure
travelingCompanionDistanceMeter = {
    lastPos = {
        x,
        y,
        z,
        timeTick,
    },
    speedPoints = {
        speedPos,
        speedSize,
        speedVals,
        speedReady,
    },
    state = {
        frameCounter,
        displayed,
    },
	output = {
		distanceTraveled,
		immediateSpeed,
        topImmediateSpeed,
        speed,
        topSpeed,
	},
};

-- The c-tor
function travelingCompanionDistanceMeter:new()
    -- Initialize the travelingCompanionDistanceMeter
    registerForEvent('onInit', function()
        self:clear(true);
    end)

    -- Reset the travelingCompanionDistanceMeter
    registerHotkey("tcdmReset", "Reset TCDM", function()
        self:clear(false);
    end)

    -- Toggle the travelingCompanionDistanceMeter
    registerHotkey("tcdmMeterToggle", "Toggle TCDM", function()
        self:toggleDisplayed();
    end)

    -- The main loop
    registerForEvent('onDraw', function()
        -- Don't enter here if the player isn't in the game
        if self:isOutsideTheGame() then
            return;
        end

        -- Show the UI
        if(self:isDisplayed()) then
            self:showTheUI();
        end

        -- Literally the frame counter, as long as the notInGame func is false
        self.state.frameCounter = self.state.frameCounter + 1;

        -- Do the computation only on every few frames in
        if(self.state.frameCounter % 2 ~= 0) then
            return;
        end

        -- Collect all the external data
        local currPos = Game.GetPlayer():GetWorldPosition();
        local currTime = os.clock(); -- Game.GetSimTime():ToFloat() too, but it's quite imprecise

        -- Manage the speed points
        if(self:isDisplayed()) then
            self:manageSpeedPoints(currPos, currTime);
        end

        -- Only skip computations on the first frame
        if(self.lastPos.timeTick ~= -1) then
            -- Compute all derived values
            self:computeDistanceAndImmediateSpeed(currPos, currTime);

            -- Compute the complex speed if applicable
            if(self:isDisplayed() and self.speedPoints.speedReady) then
                self:computeTrailingSpeed();
            end
        end

        -- Update all values for the next iteration
        self.lastPos.x = currPos.x;
        self.lastPos.y = currPos.y;
        self.lastPos.z = currPos.z;
        self.lastPos.timeTick = currTime;
    end)

    return self;
end

--------------------------------------------------------------------------------
-- UI --------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- Displays the travelingCompanionDistanceMeter UI
function travelingCompanionDistanceMeter:showTheUI()
    ImGui.SetNextWindowPos(50, 50, ImGuiCond.Always);
	ImGui.SetNextWindowSize(380, 130, ImGuiCond.Always);
	ImGui.PushStyleColor(ImGuiCol.Text, 0xFF00DDFF); -- 0xAABBGGRR
	ImGui.PushStyleColor(ImGuiCol.WindowBg, 0x99000000);
    ImGui.PushStyleColor(ImGuiCol.Border, 0x00000000);        
	
	if ImGui.Begin("TCDM") then
		ImGui.SetWindowFontScale(1.15);
		ImGui.Text("Traveled: " .. string.format(
            "%.5f", self.output.distanceTraveled) .. " m\n"
            .. string.format("% 5.0f km/h (immediate); top=%.2f km/h\n", self.output.immediateSpeed, self.output.topImmediateSpeed)
            .. string.format("% 5.0f km/h (trailing); top=%.2f km/h\n", self.output.speed, self.output.topSpeed)
            .. string.format("x=%.2f y=%.2f z=%.2f t=%.3f", self.lastPos.x, self.lastPos.y, self.lastPos.z, self.lastPos.timeTick)
        );
		ImGui.SetWindowFontScale(1.0);
	end
	
	ImGui.PopStyleColor()
	ImGui.PopStyleColor()
    ImGui.PopStyleColor()
	ImGui.End()
end

--------------------------------------------------------------------------------
-- Data collectors -------------------------------------------------------------
--------------------------------------------------------------------------------

-- Manages recording and rotating the speed points
function travelingCompanionDistanceMeter:manageSpeedPoints(currPos, currTime)
    self.speedPoints.speedPos = self.speedPoints.speedPos + 1;
    if(self.speedPoints.speedPos == self.speedPoints.speedSize + 1) then
        self.speedPoints.speedReady = true;
        self.speedPoints.speedPos = 1;
    end
    self.speedPoints.speedVals[self.speedPoints.speedPos][1] = currPos.x;
    self.speedPoints.speedVals[self.speedPoints.speedPos][2] = currPos.y;
    self.speedPoints.speedVals[self.speedPoints.speedPos][3] = currPos.z;
    self.speedPoints.speedVals[self.speedPoints.speedPos][4] = currTime;
end

--------------------------------------------------------------------------------
-- Computations ----------------------------------------------------------------
--------------------------------------------------------------------------------

-- Computes distance and speed since the last recorded point
function travelingCompanionDistanceMeter:computeDistanceAndImmediateSpeed(currPos, currTime)
    local length = math.sqrt(
        (currPos.x - self.lastPos.x)^2
        + (currPos.y - self.lastPos.y)^2
        + (currPos.z - self.lastPos.z)^2
    );
    local timeDiff = currTime - self.lastPos.timeTick;

    -- Update all computed output values
    if length > 0.001 then
        self.output.distanceTraveled = self.output.distanceTraveled + length;
    end
    self.output.immediateSpeed = (length / timeDiff) * 3.6; -- metres per second converted to km/h

    -- Update the top speed (where applicable)
    if(self.output.topImmediateSpeed < self.output.immediateSpeed) then
        self.output.topImmediateSpeed = self.output.immediateSpeed
    end
end

-- Computes the trailing speed based on the recorded points
-- This can get as complex as it needs to be. But, for now,
-- it is taking the oldest and the latest known data points,
-- and approximating the information from them.
function travelingCompanionDistanceMeter:computeTrailingSpeed()
    -- Determine the location of the oldest data point
    local theOtherPos = self.speedPoints.speedPos + 1;
    if theOtherPos == self.speedPoints.speedSize + 1 then
        theOtherPos = 1;
    end

    -- Obtain the two data points
    local item1 = self.speedPoints.speedVals[theOtherPos];
    local item2 = self.speedPoints.speedVals[self.speedPoints.speedPos];

    -- Determine the square of the distance traveled between
    -- the two data points
    local spacebetweenraw =
        (item1[1] - item2[1])^2
        + (item1[2] - item2[2])^2
        + (item1[3] - item2[3])^2
    ;
    -- Determine the time traveled between the two data points
    local timebetween = item2[4] - item1[4];

    -- If the space difference is sufficiently small,
    -- label it as zero and wrap up.
    if(spacebetweenraw < 0.001) then
        self.output.speed = 0;
    else
        -- Otherwise perform the computations
        self.output.speed = 3.6 * math.sqrt(spacebetweenraw) / timebetween;

        -- Update the top speed (where applicable)
        if(self.output.topSpeed < self.output.speed) then
            self.output.topSpeed = self.output.speed;
        end
    end
end

--------------------------------------------------------------------------------
-- Helpers ---------------------------------------------------------------------
--------------------------------------------------------------------------------

-- Tells if the travelingCompanionDistanceMeter should be displayed
function travelingCompanionDistanceMeter:isDisplayed()
    return self.state.displayed;
end

-- Toggles whether the travelingCompanionDistanceMeter should be displayed
function travelingCompanionDistanceMeter:toggleDisplayed()
    self.state.displayed = not self.state.displayed;
end

-- Tells if the player is *not* in the game
function travelingCompanionDistanceMeter:isOutsideTheGame()
    return
        Game == nil
        or Game.GetPlayer() == nil
        or Game.GetSystemRequestsHandler():IsPreGame()
        or Game.GetSystemRequestsHandler():IsGamePaused()
        or Game.GetPhotoModeSystem():IsPhotoModeActive()
    ;
end

-- Clear the object; the only option that may avoid this is the
-- :isDisplayed() state of the window
function travelingCompanionDistanceMeter:clear(alsoResetDisplayedState)
    self.output.distanceTraveled = 0;
    self.output.immediateSpeed = 0;
    self.output.topImmediateSpeed = 0;
    self.output.speed = 0;
    self.output.topSpeed = 0;
    self.state.frameCounter = 0;
    if(alsoResetDisplayedState) then
        self.state.displayed = false; -- The companion isn't displayed by default
    end

    self.lastPos.timeTick = -1.0;
    self.lastPos.x = 0;
    self.lastPos.y = 0;
    self.lastPos.z = 0;

    -- Speed points
    self.speedPoints.speedPos = 0;
    self.speedPoints.speedSize = 15;
    self.speedPoints.speedVals = {};
    for i=1,self.speedPoints.speedSize do
        self.speedPoints.speedVals[i] = {0, 0, 0, 0}; -- x, y, z, t
    end
    self.speedPoints.speedReady = false;
end

-- Produce and return the object for CET to work with
return travelingCompanionDistanceMeter:new();