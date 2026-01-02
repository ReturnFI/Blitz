document.addEventListener("DOMContentLoaded", function () {

    const container = document.querySelector("[data-get-file-url]");
    if (!container) return;

    const getFileUrl = container.dataset.getFileUrl;
    const setFileUrl = container.dataset.setFileUrl;

    const editorContainer = document.getElementById("jsoneditor");
    const saveBtn = document.getElementById("save-button");
    const restoreBtn = document.getElementById("restore-button");

    if (!editorContainer) return;

    const editor = new JSONEditor(editorContainer, {
        mode: "tree",
        modes: ["tree", "code"],
        search: true,
        history: true
    });

    // Load file
    fetch(getFileUrl)
        .then(res => res.json())
        .then(data => {
            editor.set(data);
        })
        .catch(() => {
            Swal.fire("Error", "Failed to load config file", "error");
        });

    // Save
    saveBtn.addEventListener("click", () => {
        const data = editor.get();

        fetch(setFileUrl, {
            method: "POST",
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify(data)
        })
        .then(res => res.json())
        .then(() => {
            Swal.fire("Saved", "Config saved successfully", "success");
        })
        .catch(() => {
            Swal.fire("Error", "Failed to save config", "error");
        });
    });

    // Restore
    restoreBtn.addEventListener("click", () => {
        fetch(getFileUrl)
            .then(res => res.json())
            .then(data => {
                editor.set(data);
                Swal.fire("Restored", "Config restored", "info");
            })
            .catch(() => {
                Swal.fire("Error", "Failed to restore config", "error");
            });
    });

});
