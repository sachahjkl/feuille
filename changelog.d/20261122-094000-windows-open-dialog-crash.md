type: Fixed

**Opening the file dialog on Windows no longer crashes (`0xC0000374` heap corruption).** Listing a folder that holds NTFS junctions, symbolic links or OneDrive cloud reparse points (such as a user's home or Documents folder) double-freed the entry's path string because Odin's `os.stat` aliases its input path inside `File_Info.fullpath` on reparse points; link targets and thumbnail sizes are now resolved directly from Windows without `os.stat`.
