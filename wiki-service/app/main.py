import asyncio

from fastapi import FastAPI, Depends, HTTPException, Response
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST

from app.database import engine, get_db, Base
from app.models import User, Post
from app.schemas import UserCreate, UserResponse, PostCreate, PostResponse
from app.metrics import users_created_total, posts_created_total


app = FastAPI(title="User and Post API")


# -----------------------------
# Database Health Check Helper
# -----------------------------
async def check_database():
    """
    Lightweight DB connectivity check.
    Ensures connection is opened and closed properly.
    """
    async with engine.begin() as conn:
        await conn.execute(text("SELECT 1"))


# -----------------------------
# Startup Logic (with retry)
# -----------------------------
@app.on_event("startup")
async def startup():
    """
    Ensures DB is reachable before app fully boots.
    Retries to handle Kubernetes startup race conditions.
    """
    max_retries = 10
    delay_seconds = 3

    for attempt in range(max_retries):
        try:
            async with engine.begin() as conn:
                await conn.run_sync(Base.metadata.create_all)
            return
        except Exception as e:
            if attempt == max_retries - 1:
                raise e
            await asyncio.sleep(delay_seconds)


# -----------------------------
# Health Endpoints
# -----------------------------
@app.get("/health/live")
async def live():
    """
    Liveness probe.
    Only verifies process responsiveness.
    No DB checks to avoid restart loops.
    """
    return {"status": "alive"}


@app.get("/health/ready")
async def ready():
    """
    Readiness probe.
    Continuously verifies DB connectivity.
    If DB fails, pod is removed from Service.
    """
    try:
        await check_database()
        return {"status": "ready"}
    except Exception:
        raise HTTPException(status_code=503, detail="Database not ready")


@app.get("/health/startup")
async def startup_health():
    """
    Startup probe.
    Indicates application is reachable after boot.
    """
    return {"status": "started"}


# -----------------------------
# Business Endpoints
# -----------------------------
@app.post("/users", response_model=UserResponse)
async def create_user(user: UserCreate, db: AsyncSession = Depends(get_db)):
    new_user = User(name=user.name)
    db.add(new_user)
    await db.commit()
    await db.refresh(new_user)

    users_created_total.inc()

    return UserResponse(
        id=new_user.id,
        name=new_user.name,
        created_time=new_user.created_time
    )


@app.post("/posts", response_model=PostResponse)
async def create_post(post: PostCreate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.id == post.user_id))
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    new_post = Post(content=post.content, user_id=post.user_id)
    db.add(new_post)
    await db.commit()
    await db.refresh(new_post)

    posts_created_total.inc()

    return PostResponse(
        post_id=new_post.id,
        content=new_post.content,
        user_id=new_post.user_id,
        created_time=new_post.created_time
    )


@app.get("/users/{id}", response_model=UserResponse)
@app.get("/user/{id}", response_model=UserResponse, include_in_schema=False)
async def get_user(id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.id == id))
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    return UserResponse(
        id=user.id,
        name=user.name,
        created_time=user.created_time
    )


@app.get("/posts/{id}", response_model=PostResponse)
async def get_post(id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Post).where(Post.id == id))
    post = result.scalar_one_or_none()

    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    return PostResponse(
        post_id=post.id,
        content=post.content,
        user_id=post.user_id,
        created_time=post.created_time
    )


@app.get("/")
async def root():
    return {
        "message": "User and Post API",
        "endpoints": {
            "POST /users": "Create a new user",
            "POST /posts": "Create a new post",
            "GET /user/{id}": "Get user by ID",
            "GET /posts/{id}": "Get post by ID",
            "GET /metrics": "Prometheus metrics"
        }
    }


@app.get("/metrics")
async def metrics():
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST
    )