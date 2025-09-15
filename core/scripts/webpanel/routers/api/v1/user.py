import json
from typing import List
from fastapi import APIRouter, HTTPException
from .schema.user import (
    UserListResponse, 
    UserInfoResponse, 
    AddUserInputBody, 
    EditUserInputBody, 
    UserUriResponse, 
    AddBulkUsersInputBody, 
    UsernamesRequest
)
from .schema.response import DetailResponse
import cli_api

router = APIRouter()


@router.get('/', response_model=UserListResponse)
async def list_users_api():
    """
    Get a list of all users.

    Returns:
        List of user dictionaries.
    Raises:
        HTTPException: if no users are found, or if an error occurs.
    """
    try:
        if res := cli_api.list_users():
            return res
        raise HTTPException(status_code=404, detail='No users found.')
    except Exception as e:
        raise HTTPException(status_code=400, detail=f'Error: {str(e)}')


@router.post('/', response_model=DetailResponse, status_code=201)
async def add_user_api(body: AddUserInputBody):
    try:
        cli_api.get_user(body.username)
        raise HTTPException(status_code=409,
                            detail=f"User '{body.username}' already exists.")
    except cli_api.CommandExecutionError:
        pass
    except json.JSONDecodeError as e:
        raise HTTPException(status_code=500,
                            detail=f"{str(e)}")

    try:
        cli_api.add_user(body.username, body.traffic_limit, body.expiration_days, body.password, body.creation_date, body.unlimited)
        return DetailResponse(detail=f'User {body.username} has been added.')
    except cli_api.CommandExecutionError as e:
        if "User already exists" in str(e):
            raise HTTPException(status_code=409,
                                detail=f"User '{body.username}' already exists.")
        raise HTTPException(status_code=400,
                            detail=f'Failed to add user {body.username}: {str(e)}')
    except cli_api.PasswordGenerationError as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to generate password for user '{body.username}': {str(e)}")
    except cli_api.InvalidInputError as e:
         raise HTTPException(status_code=422, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"An unexpected error occurred while adding user '{body.username}': {str(e)}")


@router.post('/bulk/', response_model=DetailResponse, status_code=201)
async def add_bulk_users_api(body: AddBulkUsersInputBody):
    """
    Add multiple users in bulk.
    """
    try:
        cli_api.bulk_user_add(
            traffic_gb=body.traffic_gb,
            expiration_days=body.expiration_days,
            count=body.count,
            prefix=body.prefix,
            start_number=body.start_number,
            unlimited=body.unlimited
        )
        return DetailResponse(detail=f"Successfully started adding {body.count} users with prefix '{body.prefix}'.")
    except cli_api.CommandExecutionError as e:
        raise HTTPException(status_code=400,
                            detail=f'Failed to add bulk users: {str(e)}')
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"An unexpected error occurred while adding bulk users: {str(e)}")

@router.post('/uri/bulk', response_model=List[UserUriResponse])
async def show_multiple_user_uris_api(request: UsernamesRequest):
    """
    Get URI information for multiple users in a single request for efficiency.
    """
    if not request.usernames:
        return []
        
    try:
        uri_data_list = cli_api.show_user_uri_json(request.usernames)
        if not uri_data_list:
            raise HTTPException(status_code=404, detail='No URI data found for the provided users.')
        
        valid_responses = [data for data in uri_data_list if not data.get('error')]
        
        return valid_responses
    except cli_api.ScriptNotFoundError as e:
        raise HTTPException(status_code=500, detail=f'Server script error: {str(e)}')
    except cli_api.CommandExecutionError as e:
        raise HTTPException(status_code=400, detail=f'Error executing script: {str(e)}')
    except Exception as e:
        raise HTTPException(status_code=400, detail=f'Unexpected error: {str(e)}')


@router.post('/bulk-delete', response_model=DetailResponse)
async def bulk_remove_users_api(body: UsernamesRequest):
    if not body.usernames:
        raise HTTPException(status_code=400, detail="No usernames provided.")
    try:
        cli_api.kick_users_by_name(body.usernames)
        cli_api.traffic_status(display_output=False)
        cli_api.remove_users(body.usernames)
        return DetailResponse(detail=f'Users have been removed.')
    except Exception as e:
        raise HTTPException(status_code=400, detail=f'Error: {str(e)}')


@router.get('/{username}', response_model=UserInfoResponse)
async def get_user_api(username: str):
    """
    Get the details of a user.

    Args:
        username: The username of the user to get.

    Returns:
        A user dictionary.

    Raises:
        HTTPException: if the user is not found, or if an error occurs.
    """
    try:
        user_data = cli_api.get_user(username)
        if not user_data:
            raise HTTPException(status_code=404, detail=f'User {username} not found.')
        
        if '_id' in user_data:
            user_data['username'] = user_data.pop('_id')
            
        return user_data
    except json.JSONDecodeError as e:
        raise HTTPException(status_code=500, detail=f"Failed to parse user data from CLI: {e}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f'An unexpected error occurred: {str(e)}')


@router.patch('/{username}', response_model=DetailResponse)
async def edit_user_api(username: str, body: EditUserInputBody):
    """
    Edit a user's details.

    Args:
        username: The username of the user to edit.
        body: An instance of EditUserInputBody containing the new user details.

    Returns:
        A DetailResponse with a message indicating the user has been edited.

    Raises:
        HTTPException: if an error occurs while editing the user.
    """
    try:
        cli_api.kick_users_by_name([username])
        cli_api.traffic_status(display_output=False)
        cli_api.edit_user(username, body.new_username, body.new_traffic_limit, body.new_expiration_days,
                          body.renew_password, body.renew_creation_date, body.blocked, body.unlimited_ip)
        return DetailResponse(detail=f'User {username} has been edited.')
    except Exception as e:
        raise HTTPException(status_code=400, detail=f'Error: {str(e)}')


@router.delete('/{username}', response_model=DetailResponse)
async def remove_user_api(username: str):
    """
    Remove a user.

    Args:
        username: The username of the user to remove.

    Returns:
        A DetailResponse with a message indicating the user has been removed.

    Raises:
        HTTPException: 404 if the user is not found, 400 if another error occurs.
    """
    try:
        user = cli_api.get_user(username)
        if not user:
            raise HTTPException(status_code=404, detail=f'User {username} not found.')
        
        cli_api.kick_users_by_name([username])
        cli_api.traffic_status(display_output=False)
        cli_api.remove_users([username])
        return DetailResponse(detail=f'User {username} has been removed.')
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=f'Error: {str(e)}')


@router.get('/{username}/reset', response_model=DetailResponse)
async def reset_user_api(username: str):
    """
    Resets a user.

    Args:
        username: The username of the user to reset.

    Returns:
        A DetailResponse with a message indicating the user has been reset.

    Raises:
        HTTPException: if an error occurs while resetting the user.
    """
    try:
        user = cli_api.get_user(username)
        if not user:
            raise HTTPException(status_code=404, detail=f'User {username} not found.')
        
        cli_api.reset_user(username)
        return DetailResponse(detail=f'User {username} has been reset.')
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=f'Error: {str(e)}')

@router.get('/{username}/uri', response_model=UserUriResponse)
async def show_user_uri_api(username: str):
    """
    Get the URI information for a user in JSON format.

    Args:
        username: The username of the user.

    Returns:
        UserUriResponse: An object containing URI information for the user.

    Raises:
        HTTPException: 404 if the user is not found, 400 if another error occurs.
    """
    try:
        uri_data_list = cli_api.show_user_uri_json([username])
        if not uri_data_list:
            raise HTTPException(status_code=404, detail=f'URI for user {username} not found.')
        
        uri_data = uri_data_list[0]
        if uri_data.get('error'):
            raise HTTPException(status_code=404, detail=f"{uri_data['error']}")
        
        return UserUriResponse(**uri_data)
    except cli_api.ScriptNotFoundError as e:
        raise HTTPException(status_code=500, detail=f'Server script error: {str(e)}')
    except cli_api.CommandExecutionError as e:
        raise HTTPException(status_code=400, detail=f'Error executing script: {str(e)}')
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=f'Unexpected error: {str(e)}')