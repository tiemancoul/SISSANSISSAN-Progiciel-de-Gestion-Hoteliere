<?php

namespace Tests\Feature;

use App\Models\Hotel;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class HotelIsolationTest extends TestCase
{
    use RefreshDatabase;

    public function test_hotel_admin_only_lists_staff_of_their_hotel(): void
    {
        $admin = User::factory()->hotelAdmin()->create();
        $colleague = User::factory()->for($admin->hotel)->create();
        $stranger = User::factory()->create();

        Sanctum::actingAs($admin);
        $ids = collect($this->getJson('/api/users')->assertOk()->json())->pluck('id');

        $this->assertEqualsCanonicalizing([$admin->id, $colleague->id], $ids->all());
        $this->assertNotContains($stranger->id, $ids);
    }

    public function test_hotel_admin_cannot_create_staff_in_another_hotel(): void
    {
        $admin = User::factory()->hotelAdmin()->create();
        $other = Hotel::factory()->create();

        Sanctum::actingAs($admin);
        $this->postJson('/api/users', [
            'name' => 'Intrus', 'email' => 'x@demo.ml', 'password' => 'secret123',
            'role' => 'receptionist', 'hotel_id' => $other->id,
        ])->assertCreated()->assertJsonPath('hotel_id', $admin->hotel_id);
    }

    public function test_hotel_admin_cannot_edit_another_hotels_user(): void
    {
        $admin = User::factory()->hotelAdmin()->create();
        $stranger = User::factory()->create();

        Sanctum::actingAs($admin);
        $this->patchJson("/api/users/{$stranger->id}", ['is_active' => false])->assertNotFound();
        $this->assertTrue($stranger->fresh()->is_active);
    }

    public function test_nobody_can_create_a_super_admin_through_the_api(): void
    {
        Sanctum::actingAs(User::factory()->hotelAdmin()->create());

        $this->postJson('/api/users', [
            'name' => 'X', 'email' => 'x@demo.ml', 'password' => 'secret123', 'role' => 'super_admin',
        ])->assertUnprocessable();
    }

    public function test_receptionist_cannot_manage_users_or_hotels(): void
    {
        Sanctum::actingAs(User::factory()->create());

        $this->getJson('/api/users')->assertForbidden();
        $this->getJson('/api/hotels')->assertForbidden();
    }

    public function test_super_admin_creates_hotels_and_their_staff(): void
    {
        Sanctum::actingAs(User::factory()->superAdmin()->create());

        $hotelId = $this->postJson('/api/hotels', ['name' => 'Hôtel Sikasso', 'slug' => 'sikasso'])
            ->assertCreated()->json('id');

        $this->postJson('/api/users', [
            'name' => 'Gérant', 'email' => 'g@sikasso.ml', 'password' => 'secret123',
            'role' => 'hotel_admin', 'hotel_id' => $hotelId,
        ])->assertCreated()->assertJsonPath('hotel_id', $hotelId);
    }
}
