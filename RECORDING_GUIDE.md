# Recording the Demo GIF

## Quick Recording Steps (macOS)

1. **Prepare your terminal:**
   ```bash
   # Set a clean prompt for recording
   export PS1="$ "
   
   # Clear the screen
   clear
   
   # Resize terminal to about 80x24 (smaller is better for GIFs)
   ```

2. **Start QuickTime recording:**
   - Open QuickTime Player
   - File → New Screen Recording
   - Click the down arrow, select "Record Selected Portion"
   - Select just your terminal window
   - Click Record

3. **Run the demo:**
   ```bash
   cd ~/Desktop/claude-conversation-extractor
   ./demo-script.sh
   ```

4. **Stop recording** when the script finishes

5. **Convert to GIF:**
   - Option A: Use [Gifski](https://gif.ski) (best quality)
   - Option B: Use [CloudConvert](https://cloudconvert.com/mov-to-gif)
   - Option C: Use ffmpeg:
     ```bash
     ffmpeg -i demo.mov -vf "fps=10,scale=800:-1" -gifflags +transdiff demo.gif
     ```

## Tips for Best Quality

- Keep terminal window small (80x24 or 100x30)
- Use a clean terminal theme
- Hide any personal information in prompts
- Keep the recording under 30 seconds
- Aim for file size under 5MB for GitHub