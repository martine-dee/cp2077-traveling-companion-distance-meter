require "config.lua";

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
        totalLength,
        totalTime,
    },
    state = {
        frameCounter,
        displayed,
        uiScale,
    },
    constants = {
        std_gravity_pos = 9.80665, -- m/s^2; inverted sign
        display_update_interval = 0.15, -- seconds
    },
	output = {
		distanceTraveled,
        speed,
        topSpeed,
        displayedSpeed,
        displayedSpeedTime,
        accel,              -- Acceleration vector (xyz Gs)
        accelint,           -- Acceleration intensity (Gs)
        displayedAccel,     -- The displayed acceleration intensity (Gs)
        displayedAccelTime, -- The last time displayed acceleration was updated
        accelMax,           -- The maximal recorded acceleration intensity (Gs)

        -- Breakdown of the acceleration vector into player's XYZ
        accelX,
        accelY,
        accelZ,
        accelXMax,
        accelYMax,
        accelZMax,
        accelXMin,
        accelYMin,
        accelZMin,
	},
};

tcdm = nil;

-- The c-tor
function travelingCompanionDistanceMeter:new()

    tcdm = self;

    -- Initialize the travelingCompanionDistanceMeter
    registerForEvent('onInit', function()
        self:clear(true);

        if travelingCompanionDistanceMeterConfig.overrideVehicleSpeedometer then
            if Override ~= nil then
                -- The speed reading in the 3rd person cam
                if(travelingCompanionDistanceMeterConfig.convertSpeedometerToMPH) then
                    Override("hudCarController", "OnSpeedValueChanged", function (zelf, speedValue)
                        inkTextRef.SetText(zelf.SpeedValue, string.format("%.0f", tcdm.output.displayedSpeed * 0.621371192) .. " mph" );
                    end)

                    -- The speedometer inside the vehicle
                    Override("speedometerLogicController", "OnSpeedValueChanged", function (zelf, speedValue)
                        inkTextRef.SetText(zelf.speedTextWidget, string.format("%.0f", tcdm.output.displayedSpeed * 0.621371192) .. " mph");
                    end)
                else
                    -- The speed reading in the 3rd person cam
                    Override("hudCarController", "OnSpeedValueChanged", function (zelf, speedValue)
                        inkTextRef.SetText(zelf.SpeedValue, string.format("%.0f", tcdm.output.displayedSpeed) .. " km/h");
                    end)

                    -- The speedometer inside the vehicle
                    Override("speedometerLogicController", "OnSpeedValueChanged", function (zelf, speedValue)
                        inkTextRef.SetText(zelf.speedTextWidget, string.format("%.0f", tcdm.output.displayedSpeed) .. " km/h");
                    end)
                end
            else
                print("TCDM: Can't override the speedometer. Do you have Codeware? Did it load?");
            end
        end
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
        local player = Game.GetPlayer();
        local currPos = player:GetWorldPosition();
        local currTime = os.clock(); -- Game.GetSimTime():ToFloat() too, but it's quite imprecise

        -- Only compute things if this isn't the first frame
        if(self.lastPos.timeTick ~= -1) then
            -- Compute the length between the currPos and the lastPos
            local length = math.sqrt(
                (currPos.x - self.lastPos.x)^2
                + (currPos.y - self.lastPos.y)^2
                + (currPos.z - self.lastPos.z)^2
            );

            -- Actually, skip anything and everything if the length isn't sufficient
            if length > 0.001 then
                -- Update distance traveled
                self.output.distanceTraveled = self.output.distanceTraveled + length;

                -- Only compute the speed-related info if the tool is displayed, or
                -- if TCDM is overriding the vehicle's speedometer
                if(self:isDisplayed() or travelingCompanionDistanceMeterConfig.overrideVehicleSpeedometer) then
                    local timeDiff = currTime - self.lastPos.timeTick;

                    -------------------------------------------
                    -- Manage the speed points and derived data
                    -------------------------------------------
                    local sp = self.speedPoints;
                    sp.speedPos = sp.speedPos + 1;
                    if(sp.speedPos == sp.speedSize + 1) then
                        sp.speedPos = 1;

                        -- Once the speeds have become ready, compute the sum of all lengths
                        -- But, do this only if the speeds aren't marked as ready yet
                        if(not sp.speedReady) then 
                            sp.speedReady = true;
                            sp.totalLength = 0;
                            for i=1,sp.speedSize do
                                sp.totalLength = sp.totalLength + sp.speedVals[i][5];
                            end
                        end
                    end

                    local speedPos = sp.speedPos;

                    -- Maintain the .totalTime
                    local theOldestPos = speedPos + 1;
                    if theOldestPos == sp.speedSize + 1 then
                        theOldestPos = 1;
                    end
                    sp.totalTime = currTime - sp.speedVals[theOldestPos][4];

                    -- Maintain the .totalLength
                    -- Remove the length from the point that will be overwritten
                    -- and add length of the point that will be added in its place
                    sp.totalLength =
                        sp.totalLength
                        - sp.speedVals[speedPos][5]
                        + length
                    ;

                    -- Write the new point
                    sp.speedVals[speedPos][1] = currPos.x;
                    sp.speedVals[speedPos][2] = currPos.y;
                    sp.speedVals[speedPos][3] = currPos.z;
                    sp.speedVals[speedPos][4] = currTime;
                    sp.speedVals[speedPos][5] = length;
                end

                -- Compute the values derived from speed points if all of them are ready
                if(self.speedPoints.speedReady) then
                    -- Compute the output speed
                    self.output.speed = 3.6 * self.speedPoints.totalLength / self.speedPoints.totalTime;

                    -- Update the top speed (where applicable)
                    if(self.output.topSpeed < self.output.speed) then
                        self.output.topSpeed = self.output.speed;
                    end

                    -- Update the displayed speed
                    if((self.output.displayedSpeedTime == -1) or (currTime - self.output.displayedSpeedTime) > self.constants.display_update_interval) then
                        self.output.displayedSpeed = self.output.speed;
                        self.output.displayedSpeedTime = currTime;
                    end

                    -- Update acceleration's internal and displayed values
                    -- ... if TCDM is displayed.
                    if(self:isDisplayed()) then
                        local sp = self.speedPoints;
                        local speedPos = sp.speedPos;

                        -- The index of the oldest data point
                        local v1pos = speedPos+1;
                        if v1pos > sp.speedSize then
                            v1pos = 1;
                        end

                        -- The index of the newest data point
                        local v2pos = speedPos;

                        -- The time difference to fulfill $vvec
                        local tdiff = sp.speedVals[v2pos][4] - sp.speedVals[v1pos][4];

                        -- Record the movement vector and $tdiff for later use
                        sp.speedVals[speedPos][7] = {
                            -- The space vector from the oldest to the newest data point
                            {
                                sp.speedVals[v2pos][1] - sp.speedVals[v1pos][1],
                                sp.speedVals[v2pos][2] - sp.speedVals[v1pos][2],
                                sp.speedVals[v2pos][3] - sp.speedVals[v1pos][3],
                            },
                            tdiff,
                            {0, 0, 0}, -- Slot for acceleration vector, in m/s^2
                            0,         -- Slot for acceleration intensity, in m/s^2
                        };

                        -- If the oldest data point has been initialized, then computation
                        -- of acceleration values can begin. To check this, $tdiff of the
                        -- oldest point in the dataset is used. It ought to be greater
                        -- than zero.
                        if(travelingCompanionDistanceMeterConfig.showGForce and sp.speedVals[v1pos][7][2] > 0) then
                            local sgp = self.constants.std_gravity_pos;

                            -- The oldest data point (speed diff vs time)
                            local vvec1 = sp.speedVals[v1pos][7][1];
                            local t1 = sp.speedVals[v1pos][7][2];

                            -- The newest data point (speed diff vs time)
                            local vvec2 = sp.speedVals[v2pos][7][1];
                            local t2 = sp.speedVals[v2pos][7][2];

                            -- The time difference between the two said data points
                            local tdiff = sp.speedVals[v2pos][4] - sp.speedVals[v1pos][4];

                            -- The acceleration vector,
                            -- i.e. the speed difference between the two data points, per time
                            local vaccel = {
                                (vvec2[1]/t2 - vvec1[1]/t1) / tdiff,
                                (vvec2[2]/t2 - vvec1[2]/t1) / tdiff,
                                (vvec2[3]/t2 - vvec1[3]/t1) / tdiff + sgp,
                            };

                            -- Write the acceleration vector and its intensity to the current data point
                            sp.speedVals[v2pos][7][3] = vaccel;
                            sp.speedVals[v2pos][7][4] = math.sqrt(vaccel[1]^2 + vaccel[2]^2 + vaccel[3]^2);

                            -- Write the acceleration vector and intensity (in Gs)
                            -- into the self.output section
                            self.output.accel[1] = vaccel[1] / sgp;
                            self.output.accel[2] = vaccel[2] / sgp;
                            self.output.accel[3] = vaccel[3] / sgp;
                            self.output.accelint = sp.speedVals[v2pos][7][4] / sgp;

                            -- Update the displayed acceleration at regular intervals
                            if((self.output.displayedAccelTime == -1)
                                or ((currTime - self.output.displayedAccelTime) > self.constants.display_update_interval)
                            ) then
                                self.output.displayedAccel = self.output.accelint;
                                self.output.displayedAccelTime = currTime;

                                self:computeAccelComponents(vaccel);
                            end

                            -- Maintain the value of maximum recorded acceleration
                            if(self.output.accelint > self.output.accelMax) then
                                self.output.accelMax = self.output.accelint;
                                self:computeAccelComponents(vaccel);
                            end
                        end
                    end
                end
            else
                -- Set all for the standing still values
                self.output.speed = 0;
                self.output.displayedSpeed = 0;
                self.output.displayedAccel = 1;
                self.output.accelint = 0;
                self.output.accel[1] = 0;
                self.output.accel[2] = 0;
                self.output.accel[3] = -1;

                self:computeAccelComponents({0, 0, self.constants.std_gravity_pos});
                self:resetSpeedPoints();
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

-- Computation of acceleration breakdown to player's XYZ
function travelingCompanionDistanceMeter:computeAccelComponents(vaccel)
    if not travelingCompanionDistanceMeterConfig.showGComponents then
        return;
    end

    -- Get the player's perspective
    local currTr = Game.GetPlayer():GetWorldTransform();
    local playerX = currTr:GetForward();
    local playerY = currTr:GetRight();
    playerY.x = -playerY.x;
    playerY.y = -playerY.y;
    playerY.z = -playerY.z;
    local playerZ = currTr:GetUp();

    -- Project the acceleration vector onto player's XYZ
    local sgp = self.constants.std_gravity_pos;
    local aX = (playerX.x * vaccel[1] + playerX.y * vaccel[2] + playerX.z * vaccel[3]) / sgp;
    local aY = (playerY.x * vaccel[1] + playerY.y * vaccel[2] + playerY.z * vaccel[3]) / sgp;
    local aZ = (playerZ.x * vaccel[1] + playerZ.y * vaccel[2] + playerZ.z * vaccel[3]) / sgp;

    -- Write the results into slots for displaying int TCDM
    local so = self.output;
    so.accelX = aX;
    so.accelY = aY;
    so.accelZ = aZ;

    -- Maintain the min and max values (also displayed)
    if(so.accelXMax < aX) then
        so.accelXMax = aX;
    end
    if(so.accelYMax < aY) then
        so.accelYMax = aY;
    end
    if(so.accelZMax < aZ) then
        so.accelZMax = aZ;
    end
    if(so.accelXMin > aX) then
        so.accelXMin = aX;
    end
    if(so.accelYMin > aY) then
        so.accelYMin = aY;
    end
    if(so.accelZMin > aZ) then
        so.accelZMin = aZ;
    end
end

--------------------------------------------------------------------------------
-- UI --------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- Determines the UI scale based on player's screen resolution
function travelingCompanionDistanceMeter:refreshUIScale()
    local displayWidth, displayHeight = GetDisplayResolution();
    self.state.uiScale = displayHeight / 1080.0;
end

-- Displays the travelingCompanionDistanceMeter UI
function travelingCompanionDistanceMeter:showTheUI()
    local scale = self.state.uiScale;

    if scale < 0 then
        return; -- Do not draw if we don't know the scale
    end

    -- preparing
    local so = self.output;
    local slp = self.lastPos;
    local guitext_height = 105;
    local guitext = "Traveled: "
        .. string.format("%.5f", so.distanceTraveled) .. " m\n"
        .. string.format("Speed: % 5.0f km/h; top=%.2f km/h\n", so.displayedSpeed, so.topSpeed)
        .. string.format("x=%.2f y=%.2f z=%.2f t=%.3f\n", slp.x, slp.y, slp.z, slp.timeTick);
    
    if(travelingCompanionDistanceMeterConfig.showGForce) then
        guitext_height = guitext_height + 20;
        guitext = guitext .. string.format("accel= % 4.2f G (max=%.2f G)", so.displayedAccel, so.accelMax);

        if(travelingCompanionDistanceMeterConfig.showGComponents) then
            guitext_height = guitext_height + 60;
            guitext = guitext
                .. string.format("\n  x= % 4.2f G (min=%.2f G, max=%.2f G)\n", so.accelX, so.accelXMin, so.accelXMax)
                .. string.format("  y= % 4.2f G (min=%.2f G, max=%.2f G)\n", so.accelY, so.accelYMin, so.accelYMax)
                .. string.format("  z= % 4.2f G (min=%.2f G, max=%.2f G)\n", so.accelZ, so.accelZMin, so.accelZMax);
        end
    end

    -- drawing
    ImGui.SetNextWindowPos(50, 50, ImGuiCond.FirstUseEver);
    ImGui.SetNextWindowSize(380*scale, guitext_height *scale, ImGuiCond.Appearing);
    ImGui.PushStyleColor(ImGuiCol.Text, 0xFF00DDFF); -- 0xAABBGGRR
    ImGui.PushStyleColor(ImGuiCol.WindowBg, 0x99000000);
    ImGui.PushStyleColor(ImGuiCol.Border, 0x00000000);        
    if ImGui.Begin("TCDM") then
        ImGui.SetWindowFontScale(1.15);
        ImGui.Text(guitext);
        ImGui.SetWindowFontScale(1.0);
    end
	
    ImGui.PopStyleColor();
    ImGui.PopStyleColor();
    ImGui.PopStyleColor();
    ImGui.End();
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
    self.speedPoints.speedReady = false;

    self.output.distanceTraveled = 0;
    self.output.speed = 0;
    self.output.topSpeed = 0;
    self.output.displayedSpeed = 0;
    self.output.displayedSpeedTime = -1;

    -- Acceleration
    self.output.accel = {0, 0, -1};
    self.output.accelint = 1;
    self.output.displayedAccel = 1;
    self.output.displayedAccelTime = -1;
    self.output.accelMax = 1;
    self.output.accelX = 0;
    self.output.accelY = 0;
    self.output.accelZ = 0;
    self.output.accelXMax = 0;
    self.output.accelYMax = 0;
    self.output.accelZMax = 0;
    self.output.accelXMin = 0;
    self.output.accelYMin = 0;
    self.output.accelZMin = 0;

    self.state.frameCounter = 0;
    if(alsoResetDisplayedState) then
        self.state.displayed = false; -- The companion isn't displayed by default
    end

    self:refreshUIScale(); -- Determine self.state.uiScale

    self.lastPos.timeTick = -1.0;
    self.lastPos.x = 0;
    self.lastPos.y = 0;
    self.lastPos.z = 0;

    -- Speed points
    self:resetSpeedPoints();
end

-- Resets the recorded speed data. This usually happens on full stop.
function travelingCompanionDistanceMeter:resetSpeedPoints()
    self.speedPoints.speedPos = 0;
    self.speedPoints.speedSize = travelingCompanionDistanceMeterConfig.dataSamplingPointsCount;
    self.speedPoints.speedVals = {};
    self.speedPoints.totalLength = 0;
    self.speedPoints.totalTime = 0;
    for i=1,self.speedPoints.speedSize do
        self.speedPoints.speedVals[i] = {
            0, -- x
            0, -- y
            0, -- z
            0, -- t
            0, -- l (path length)
            0, -- v(speed)
            {  -- acceleration info
                {0, 0, 0}, -- movement vector across all data points, m
                0,         -- time diff for the movement vector, s
                {0, 0, 0}, -- current acceleration vector, 3x m/s^2
                0,         -- current acceleration intensity, m/s^2
            },
        };
    end
end

-- Produce and return the object for CET to work with
return travelingCompanionDistanceMeter:new();
