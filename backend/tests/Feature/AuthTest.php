<?php

namespace Tests\Feature;

use App\Models\Hotel;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AuthTest extends TestCase
{
    use RefreshDatabase;

    public function test_login_returns_a_token_that_opens_me(): void
    {
        $user = User::factory()->create(['email' => 'r@demo.ml']);

        $token = $this->postJson('/api/login', ['email' => 'r@demo.ml', 'password' => 'password'])
            ->assertOk()->json('token');

        $this->withToken($token)->getJson('/api/me')->assertOk()->assertJsonPath('id', $user->id)
            ->assertJsonMissingPath('password');
    }

    public function test_wrong_password_is_refused(): void
    {
        User::factory()->create(['email' => 'r@demo.ml']);

        $this->postJson('/api/login', ['email' => 'r@demo.ml', 'password' => 'nope'])->assertUnprocessable();
    }

    public function test_suspended_hotel_blocks_login_but_keeps_data(): void
    {
        $hotel = Hotel::factory()->create(['is_active' => false]);
        User::factory()->for($hotel)->create(['email' => 'r@demo.ml']);

        $this->postJson('/api/login', ['email' => 'r@demo.ml', 'password' => 'password'])->assertUnprocessable();
        $this->assertDatabaseHas('users', ['email' => 'r@demo.ml']);
    }

    public function test_logout_revokes_the_token(): void
    {
        $token = User::factory()->create()->createToken('t')->plainTextToken;

        $this->withToken($token)->postJson('/api/logout')->assertNoContent();
        $this->app['auth']->forgetGuards();
        $this->withToken($token)->getJson('/api/me')->assertUnauthorized();
    }
}
