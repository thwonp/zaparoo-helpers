#!/bin/bash

# ImageMagick 7 Game Image Composer
# Composites template, cover, and marquee images for games
# Processes multiple system directories (gba/, snes/, etc.)
#
# USAGE:
#   ./imagemagick_composer.sh
#
#   Run from the directory containing template.png and system subdirectories
#
# REQUIREMENTS:
#   - ImageMagick 7.x (magick command)
#   - Perl (for gamelist.xml parsing)
#   - template.png (638x1012 pixels) in the current directory
#   - System directories with the following structure:
#       systemname/
#       ├── covers/
#       │   ├── Game1.png
#       │   └── Game2.png
#       ├── marquees/
#       │   ├── Game1.png
#       │   └── Game2.png
#       └── gamelist.xml (optional - for proper game titles)
#
# FILE REQUIREMENTS:
#   - Cover and marquee filenames MUST match exactly (e.g., Game1.png)
#   - Images can be PNG, JPG, or JPEG format
#   - Covers can be any size (will be resized to fit 589x713 max)
#   - Marquees can be any size (will be resized to fit 589x109 max)
#
# GAMELIST.XML (Optional):
#   If present in a system directory, the script will extract proper game
#   titles from <name> tags matching the <thumbnail> path. Falls back to
#   filename if not found.
#
# OUTPUT:
#   - Creates an 'output' subdirectory in each system folder
#   - Generated images are 638x1012 pixels (same as template)
#   - Includes composited cover, marquee, and text labels
#
# EXAMPLE DIRECTORY STRUCTURE:
#   template.png
#   gba/
#   ├── covers/
#   │   └── Metroid Fusion.png
#   ├── marquees/
#   │   └── Metroid Fusion.png
#   ├── gamelist.xml
#   └── output/
#       └── Metroid Fusion.png (generated)
#
# Trap SIGINT (Ctrl+C) for clean exit
trap 'echo ""; echo "Interrupted by user. Exiting..."; exit 130' INT

# Configuration
TEMPLATE="template.png"
COVERS_SUBDIR="covers"
MARQUEES_SUBDIR="marquees"
OUTPUT_SUBDIR="output"
COVER_MAX_WIDTH=589
COVER_MAX_HEIGHT=713
MARQUEE_MAX_WIDTH=589
MARQUEE_MAX_HEIGHT=109

# Template dimensions
TEMPLATE_WIDTH=638
TEMPLATE_HEIGHT=1012

# Check if template exists
if [[ ! -f "$TEMPLATE" ]]; then
    echo "Error: Template file '$TEMPLATE' not found!"
    exit 1
fi

# Counter for processed images
total_count=0
total_skipped=0

echo "Starting image composition..."
echo "Template: $TEMPLATE (${TEMPLATE_WIDTH}x${TEMPLATE_HEIGHT})"
echo "Cover max size: ${COVER_MAX_WIDTH}x${COVER_MAX_HEIGHT}"
echo "Marquee max size: ${MARQUEE_MAX_WIDTH}x${MARQUEE_MAX_HEIGHT}"
echo ""

# Find all system directories (directories containing a 'covers' subdirectory)
for system_dir in */; do
    # Remove trailing slash
    system_dir="${system_dir%/}"
    
    COVERS_DIR="${system_dir}/${COVERS_SUBDIR}"
    MARQUEES_DIR="${system_dir}/${MARQUEES_SUBDIR}"
    OUTPUT_DIR="${system_dir}/${OUTPUT_SUBDIR}"
    
    # Check if this directory has covers subdirectory
    if [[ ! -d "$COVERS_DIR" ]]; then
        continue
    fi
    
    # Check if marquees subdirectory exists
    if [[ ! -d "$MARQUEES_DIR" ]]; then
        echo "Warning: System '$system_dir' has covers but no marquees directory, skipping..."
        continue
    fi
    
    echo "Processing system: $system_dir"
    echo "-----------------------------------"
    
    # Create output directory if it doesn't exist
    mkdir -p "$OUTPUT_DIR"
    
    # Counter for this system
    count=0
    skipped=0
    
    # Process each cover image in this system
    while IFS= read -r -d '' cover_path; do
        # Extract filename without path and extension
        cover_file=$(basename "$cover_path")
        game_name="${cover_file%.*}"
        extension="${cover_file##*.}"
        
        # Construct marquee path
        marquee_path="${MARQUEES_DIR}/${game_name}.${extension}"
        
        # Check if corresponding marquee exists
        if [[ ! -f "$marquee_path" ]]; then
            echo "  Warning: No matching marquee for '$game_name', skipping..."
            ((skipped++))
            continue
        fi
        
        # Output filename - same as input cover file
        output_path="${OUTPUT_DIR}/${cover_file}"
        
        # Prepare text for text boxes
        game_title="$game_name"
        
        # Check for gamelist.xml and extract game name if available
        gamelist_xml="${system_dir}/gamelist.xml"
        if [[ -f "$gamelist_xml" ]]; then
            found_name=$(perl -0777 -ne "
                while (/<game>(.*?)<\\/game>/sg) {
                    my \$block = \$1;
                    if (\$block =~ /<thumbnail>\\s*(.*?)\\s*<\\/thumbnail>/is) {
                        my \$thumb = \$1;
                        \$thumb =~ s{.*/}{};
                        if (\$thumb =~ /\\Q$cover_file\\E/i) {
                            if (\$block =~ /<name>\\s*(.*?)\\s*<\\/name>/is) {
                                my \$name = \$1;
                                \$name =~ s/\\s+/ /g;
                                \$name =~ s/^\\s+|\\s+\$//g;
                                print \$name;
                                last;
                            }
                        }
                    }
                }
            " "$gamelist_xml")
            
            if [[ -n "$found_name" ]]; then
                game_title="$found_name"
            fi
        fi
        
        system_name=$(echo "$system_dir" | tr '[:lower:]' '[:upper:]')
        
        echo "  Processing: $game_name"
        
        # Get cover dimensions
        cover_dimensions=$(magick identify -format "%w %h" "$cover_path")
        cover_width=$(echo "$cover_dimensions" | cut -d' ' -f1)
        cover_height=$(echo "$cover_dimensions" | cut -d' ' -f2)
        
        # Calculate actual resized dimensions (preserving aspect ratio)
        aspect_ratio_w=$((cover_width * COVER_MAX_HEIGHT))
        aspect_ratio_h=$((cover_height * COVER_MAX_WIDTH))
        
        if [ "$aspect_ratio_w" -gt "$aspect_ratio_h" ]; then
            # Width is limiting factor
            actual_cover_width=$COVER_MAX_WIDTH
            actual_cover_height=$((cover_height * COVER_MAX_WIDTH / cover_width))
        else
            # Height is limiting factor
            actual_cover_height=$COVER_MAX_HEIGHT
            actual_cover_width=$((cover_width * COVER_MAX_HEIGHT / cover_height))
        fi
        
        # Get marquee dimensions to calculate actual resized dimensions
        marquee_dimensions=$(magick identify -format "%w %h" "$marquee_path")
        marquee_width=$(echo "$marquee_dimensions" | cut -d' ' -f1)
        marquee_height=$(echo "$marquee_dimensions" | cut -d' ' -f2)
        
        # Available space: y52 to y875 (total: 823px)
        available_space=823
        
        # First, calculate how tall the marquee would be at max width
        marquee_height_at_max_width=$((marquee_height * MARQUEE_MAX_WIDTH / marquee_width))
        
        # Calculate total content height and check if it fits
        total_content=$((marquee_height_at_max_width + actual_cover_height))
        
        if [ "$total_content" -gt "$available_space" ]; then
            # Content too large - need to constrain marquee height
            max_marquee_height=$((available_space - actual_cover_height - 30))  # Keep minimum 30px total padding
            
            # Resize marquee to fit within constraints
            marquee_aspect_w=$((marquee_width * max_marquee_height))
            marquee_aspect_h=$((marquee_height * MARQUEE_MAX_WIDTH))
            
            if [ "$marquee_aspect_w" -gt "$marquee_aspect_h" ]; then
                # Width is limiting
                actual_marquee_width=$MARQUEE_MAX_WIDTH
                actual_marquee_height=$((marquee_height * MARQUEE_MAX_WIDTH / marquee_width))
            else
                # Height is limiting
                actual_marquee_height=$max_marquee_height
                actual_marquee_width=$((marquee_width * max_marquee_height / marquee_height))
            fi
            
            # Recalculate with constrained marquee
            total_content=$((actual_marquee_height + actual_cover_height))
        else
            # Content fits - use marquee at max width
            actual_marquee_width=$MARQUEE_MAX_WIDTH
            actual_marquee_height=$marquee_height_at_max_width
        fi
        
        # Calculate equal spacing: (available_space - marquee_height - cover_height) / 3
        # This gives us: [top padding] [marquee] [middle padding] [cover] [bottom padding]
        padding=$(((available_space - total_content) / 3))
        
        # Position marquee and cover
        actual_marquee_y=$((52 + padding))
        actual_cover_y=$((actual_marquee_y + actual_marquee_height + padding))
        
        # Compose the image using ImageMagick 7
        # 1. Start with template as base
        # 2. Add 1px black border around content (avoiding transparent corners)
        # 3. Resize and composite cover (with equal spacing)
        # 4. Resize and composite marquee (with equal spacing)
        # 5. Add text box 1: Game title (bottom-left at x71, y975) - Courier-Bold, black
        # 6. Add text box 2: System name (bottom-left at x396, y975) - Courier-Bold, black, all caps
        
        # First create the composite image without text
        magick "$TEMPLATE" \
            \( +clone -alpha extract -morphology erode square:1 \) \
            -compose copy_opacity -composite \
            -bordercolor black -compose over -border 1x1 \
            \( "$cover_path" -resize "${COVER_MAX_WIDTH}x${COVER_MAX_HEIGHT}" \) \
            -gravity center -geometry "+0+$((actual_cover_y - TEMPLATE_HEIGHT/2 + actual_cover_height/2))" -composite \
            \( "$marquee_path" -resize "${actual_marquee_width}x${actual_marquee_height}" \) \
            -gravity center -geometry "+0+$((actual_marquee_y - TEMPLATE_HEIGHT/2 + actual_marquee_height/2))" -composite \
            "$output_path" || {
            echo "    Error processing $game_name, continuing..."
            ((skipped++))
            continue
        }
        
        # Now add text on top - combine both text operations into one command
        magick "$output_path" \
            \( -background none -fill black -font Courier-Bold -size 174x90 -gravity West caption:"$game_title" \) \
            -gravity None -geometry +71+885 -composite \
            \( -background none -fill black -font Courier-Bold -size 174x90 -gravity East caption:"$system_name" \) \
            -gravity None -geometry +396+885 -composite \
            "$output_path" || {
            echo "    Error adding text to $game_name, continuing..."
            ((skipped++))
            continue
        }
        
        ((count++))
        
    done < <(find "$COVERS_DIR" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) -print0)
    
    echo "  System '$system_dir': Processed $count images, Skipped $skipped images"
    echo ""
    
    ((total_count += count))
    ((total_skipped += skipped))
    
done

echo "==================================="
echo "Composition complete!"
echo "Total processed: $total_count images"
echo "Total skipped: $total_skipped images"
