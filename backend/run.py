"""Development entry point: ``python run.py`` starts the API on port 8000."""

import os

import uvicorn

if __name__ == "__main__":
    uvicorn.run(
        "api.main:app",
        host=os.getenv("QDS_HOST", "0.0.0.0"),
        port=int(os.getenv("QDS_PORT", "8000")),
        reload=bool(os.getenv("QDS_RELOAD")),
    )
