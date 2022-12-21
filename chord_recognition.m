%% 1. Initialization

% Pick from several default files or (attempt to) choose your own!
audio_file = 'JazzGuitar1.wav'; % 'JazzGuitar2.wav'; % 'SimpleChords3.wav'; % 'SimpleChords1.wav'; % 'SimpleChords2.wav'; %  

filename = convertCharsToStrings(audio_file);
[audio,fs] = audioread(audio_file);
% Use mirchromagram to get chroma of audio over time
figure(1)
chroma = mirchromagram(audio_file,"Frame",1,"Wrap",1)
%figure(4)
%chroma_root = mirchromagram(audio_file,"Frame",1,"Wrap",0)
% Use get functions to find magnitude (strength) of pitches
chroma_magnitude = get(chroma,"Magnitude");
chroma_array = chroma_magnitude{1,1}{1,1};
% Establish frequency scale on vertical axis
chroma_freq = get(chroma,"ChromaFreq");
chroma_freq_array = chroma_freq{1,1}{1,1};
% Create variables for dimensions of the magnitude array
[y,x] = size(chroma_array);

% Generate templates
[pitch_templates,quality_array,quality_number_array] = generate_templates();
% Establish root_array
root_array = ["C","Db","D","Eb","E","F","Gb","G","Ab","A","Bb","B"];

%% 2. Main Loop (data collection)

% Threshold set for determining required power
% I didn't have time to work out a method to calculate a good threshold...
% These are ones I found worked reasonably well for these files!
if filename == "SimpleChords1.wav"
    threshold = .35;
elseif filename == "SimpleChords2.wav"
    threshold = .25;
elseif filename == "JazzGuitar1.wav"
    threshold = .04;
elseif filename == "JazzGuitar2.wav"
    threshold = .15;
elseif filename == "SimpleChords3.wav"
    threshold = .08;
else
    threshold = .2;
end

% Initialize cleaned_data array
cleaned_data = zeros(y,x);

% Chord storage over time: (root, quality)
chord_storage = zeros(x,2);

% Nested loop for indexing chroma_array and polarizing to 0 or 1
for i = 1:x
    % Set max chroma to 4 since more than that doesn't match a template
    max_chroma = 0;
    % Determine strongest chroma (if more than 4 are higher than threshold)
    sorted_chroma_column = sortrows([chroma_array(:,i),[1;2;3;4;5;6;7;8;9;10;11;12]],'descend');
    for j = 1:y
        if sorted_chroma_column(j,1) > threshold && max_chroma < 4
            cleaned_data(sorted_chroma_column(j,2),i) = 1;
            max_chroma = max_chroma + 1;
        end
    end
end

% Plot cleaned data (helpful for troubleshooting)
%figure(2)
%imagesc(flip(cleaned_data))

% Find quality and root of chord at time samples, store to chord_storage
for i = 1:x
    % Go through each column (time sample)
    audio_column = cleaned_data(:,i);
    % Find the number of pitches in the chord to save time
    pitch_number = find_pitch_number(audio_column);
    % Only test the templates with that number of pitches
    templates_cell = pitch_templates(pitch_number);
    templates = transpose(templates_cell{1,1});
    
    % Check each template using cycle_template_match helper function
    for template_number = 1:size(templates,2)
        % Pull out individual template to test
        template = templates(:,template_number);
        % Check template with helper function
        [match, match_index] = cycle_template_match(audio_column,template);
        % Once a match is found, save root/chord quality to chord_storage
        if match == true
            % Use find_root function to get string of chord root
            [root,root_number] = find_root(match_index);
            % Use generated quality_number_array to index the quality
            chord_quality = quality_number_array{1,pitch_number}(template_number);
            % Store to chord_storage
            chord_storage(i,1) = root_number;
            chord_storage(i,2) = chord_quality;
            break
        end
    end
end

%% 3. Data manipulation

% Clean data
cleaned_chord_storage = chord_storage;
% Take mode of 10 on either side to get rid of outliers
clean_threshold = 10;
for i = 1:size(cleaned_chord_storage,1)
    if i < clean_threshold+1
        cleaned_chord_storage(i,1) = mode(nonzeros(chord_storage(1:i+clean_threshold,1)));
        cleaned_chord_storage(i,2) = mode(nonzeros(chord_storage(1:i+clean_threshold,2)));
    elseif size(chord_storage,1)-i < clean_threshold+1
        cleaned_chord_storage(i,1) = mode(nonzeros(chord_storage(i-clean_threshold:end,1)));
        cleaned_chord_storage(i,2) = mode(nonzeros(chord_storage(i-clean_threshold:end,2)));
    else
        cleaned_chord_storage(i,1) = mode(nonzeros(chord_storage(i-clean_threshold:i+clean_threshold,1)));
        cleaned_chord_storage(i,2) = mode(nonzeros(chord_storage(i-clean_threshold:i+clean_threshold,2)));
    end
end

% Create array to condense time
% [start time, end time, chord root, chord quality]
chord_time_info = zeros(1,4);
% time_array to track time at index
time_array = linspace(0,size(audio,1)/fs,size(cleaned_chord_storage,1));
% new_chord boolean to track if the index marks a new chord
new_chord = false;
% Initialize chord_number to 1 (first chord)
chord_number = 1;
for i = 2:size(cleaned_chord_storage,1)
    % Trigger condition if there is a difference in chord root or quality
    if cleaned_chord_storage(i,1) ~= cleaned_chord_storage(i-1,1) || cleaned_chord_storage(i,2) ~= cleaned_chord_storage(i-1,2)
        % Increase chord number and set new_chord boolean to true
        chord_number = chord_number + 1;
        new_chord = true;
    end
    % Trigger condition if there is a new chord
    if new_chord
        % Fill in information from previous chord
        chord_time_info(chord_number-1,2) = time_array(i);
        chord_time_info(chord_number-1,3) = cleaned_chord_storage(i-1,1);
        chord_time_info(chord_number-1,4) = cleaned_chord_storage(i-1,2);
        % Extend array to make room for next chord and set start time
        chord_time_info = [chord_time_info; 0,0,0,0];
        chord_time_info(chord_number,1) = time_array(i);
        % Set new_chord boolean back to false
        new_chord = false;
    end
end
% Finish off array with info for last chord
chord_time_info(chord_number,2) = time_array(end);
chord_time_info(chord_number,3) = cleaned_chord_storage(end,1);
chord_time_info(chord_number,4) = cleaned_chord_storage(end,2);

% Second cleaning process to remove small time-length chords
removed_indexes = [];
for i = 2:size(chord_time_info,1)
    % If the length of a chord is less than or equal to 2 time samples
    if chord_time_info(i,2)-chord_time_info(i,1) <= time_array(3)
        % Add the duration of the small chord to the previous one
        chord_time_info(i-1,2) = chord_time_info(i,2);
        % Find indexes to remove after their times have been taken
        removed_indexes = [removed_indexes,i];
    end
end

% Remove rows from the end (so indexing isn't screwed up)
for i = 1:size(removed_indexes,2)
    chord_time_info(removed_indexes(end-i+1),:) = [];
end

% Separate time and chord info
time_info = chord_time_info(:,1:2);
chord_info = chord_time_info(:,3:4);
% Create string array for chord info
string_chord_info = strings(size(chord_info,1),2);

% Fill in new string_chord_info array with respective info for root/quality
for i = 1:size(chord_info,1)
    string_chord_info(i,1) = root_array(chord_info(i,1));
    string_chord_info(i,2) = quality_array(chord_info(i,2));
end

%% 4. Data Visualization

% Create time spacing T to get x-axis in seconds
T = linspace(0,size(audio,1)/fs,size(audio,1));

% Plot the audio file
figure(3)
plot(T,audio)
xlabel('Time (seconds)');
ylabel('Amplitude');

% Use built-in audioplayer to play the sound in MatLab
player = audioplayer(audio,fs);
% Move a playerhead every .05s
player.TimerPeriod = 0.05;
% Playerhead is simply a vertical line
playerhead = xline(0,'-',{'\^'},"LineWidth",1);
% Text is initialized to an empty string at 0,0
chord_name = text(0,0,'');

% Set function to update plot in real time,
% This line is terrible, but at the end of the day it works!
% See the handleEvent helper function below :)
set(player,'TimerFcn',{@handleEvent,playerhead,chord_name,fs,time_info,string_chord_info})

% Play the file
play(player)

%% 5. Helper Functions!

% Helper function to edit graphics in real time
function handleEvent(player,~,playerhead,chord_name,fs,time_info,string_chord_info)
    % Move the playerhead
    set(playerhead,'Value',player.CurrentSample/fs);
    % Constantly check if a chord change has occurred
    for i = 1:size(time_info, 1)
        if player.CurrentSample/fs < time_info(i,2)
            % If it has occurred, change the text to show that
            set(chord_name,'String',string_chord_info(i,1)+ " " +string_chord_info(i,2),'FontSize',24,'FontName','Snell Roundhand')
            % Move the chord along with the playerhead
            chord_name.Position = [player.CurrentSample/fs + .05*player.TotalSamples/fs,0];
            break;
        end
    end
end

% Helper function to generate chord templates
function [pitch_templates, quality_array,quality_number_array] = generate_templates()
    % Single Pitch (1 Pitch)
    single_pitch = [1,0,0,0,0,0,0,0,0,0,0,0];
    pitch_1 = [single_pitch];

    % Power Chord (2 Pitches)
    open_5 = [1,0,0,0,0,0,0,1,0,0,0,0];
    pitch_2 = [open_5];
    
    % Triads (3 Pitches)
    major_triad = [1,0,0,0,1,0,0,1,0,0,0,0];
    minor_triad = [1,0,0,1,0,0,0,1,0,0,0,0];
    diminished_triad = [1,0,0,1,0,0,1,0,0,0,0,0];
    augmented_triad = [1,0,0,0,1,0,0,0,1,0,0,0];
    sus2 = [1,0,1,0,0,0,0,1,0,0,0,0];
    sus4 = [1,0,0,0,0,1,0,1,0,0,0,0];
    pitch_3 = [major_triad; minor_triad; diminished_triad; augmented_triad; sus2; sus4];
    
    % 7th Chords (4 Pitches)
    major_7 = [1,0,0,0,1,0,0,1,0,0,0,1];
    dom_7 = [1,0,0,0,1,0,0,1,0,0,1,0];
    minor_7 = [1,0,0,1,0,0,0,1,0,0,1,0];
    half_dim_7 = [1,0,0,1,0,0,1,0,0,0,1,0];
    dim_7 = [1,0,0,1,0,0,1,0,0,1,0,0];
    pitch_4 = [major_7; dom_7; minor_7; half_dim_7; dim_7];
    
    % Bring all pitch templates together to use in a tree-like structure
    pitch_templates = {pitch_1, pitch_2, pitch_3, pitch_4};
    quality_number_array = {[11],[1],[2,3,4,5,12,13],[6,7,8,9,10]};
    % Array with qualities with indexes corresponding to the above numbers
    quality_array = ["Open","Maj","Min","Dim","Aug","Maj7","Dom7","Min7","HalfDim7","Dim7","","Sus2","Sus4"];
end

% Helper function to find number of pitches in a column of time
function pitch_counter = find_pitch_number(audio_column)
    pitch_counter = 0;
    for i = 1:length(audio_column)
        if audio_column(i) == 1 && pitch_counter < 4
            pitch_counter = pitch_counter + 1;
        end
    end
end

% Helper function to cycle a column and test for a match with a template
function [match, match_index] = cycle_template_match(audio_column, template)
    for i = 1:12
        if audio_column == template
            match = true;
            match_index = i;
            return
        else
            audio_column = circshift(audio_column,1);
        end
    end
    match = false;
    match_index = 0;
end

% Helper function to find the root given a match_index
function [root,number_root] = find_root(index)
    root_array = ["Db","D","Eb","E","F","Gb","G","Ab","A","Bb","B","C"];
    number_root_array = [2,3,4,5,6,7,8,9,10,11,12,1];
    root = root_array(13-index);
    number_root = number_root_array(13-index);
end
